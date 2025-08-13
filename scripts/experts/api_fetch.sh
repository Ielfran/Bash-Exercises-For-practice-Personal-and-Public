#!/usr/bin/env bash
#
# api.sh — Expert-level Bash utility for interacting with REST APIs
#
# Features:
# - Profiles via INI config (dev/staging/prod, etc.)
# - Auth via env vars or pass(1) password store
# - GET/POST/PUT/PATCH/DELETE
# - Data from string or file
# - Custom headers (-H)
# - jq pretty printing or query (-q)
# - Retries with backoff on network/5xx/429
# - Request timeout & connect-timeout
# - Dry run (print curl command)
# - Optional write raw/pretty output to file
# - Optional request/response logging to file
#
# Dependencies: bash>=4, curl, jq, (optional) pass

set -o pipefail

# --------------------------- Colors & Logging ---------------------------

is_tty() { [[ -t 2 ]]; }
CRED=$([[ -t 2 ]] && echo $'\e[31m')
CGRN=$([[ -t 2 ]] && echo $'\e[32m'])
CYEL=$([[ -t 2 ]] && echo $'\e[33m'])
CBLU=$([[ -t 2 ]] && echo $'\e[34m'])
CRST=$([[ -t 2 ]] && echo $'\e[0m'])

log() {
  # verbose info to stderr (timestamped)
  if [[ "$VERBOSE" == "true" ]]; then
    printf "%s[%s]%s %s\n" "${CBLU}" "$(date +'%Y-%m-%dT%H:%M:%S%z')" "${CRST}" "$*" >&2
  fi
}

die() {
  printf "%sERROR:%s %s\n" "${CRED}" "${CRST}" "$*" >&2
  exit 1
}

# --------------------------- Usage -------------------------------------

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Required:
  -p <profile>           Profile name from config (e.g. my_api_dev)
  -e <endpoint>          API endpoint path (e.g. /users/1)

Common:
  -c <config_file>       Config file path (default: ~/.api_util.conf)
  -m <method>            HTTP method: GET|POST|PUT|PATCH|DELETE (default: GET)
  -d <data>              JSON string body for POST/PUT/PATCH
  -f <file>              JSON file body for POST/PUT/PATCH
  -H <'Header: value'>   Custom header (may be repeated)
  -q <jq_query>          jq query to filter JSON (e.g. '.data[] | .name')
  -o <file>              Write pretty (or filtered) output to file
  -O <file>              Write raw JSON response to file (before jq)
  -L <log_file>          Append request/response details to this log
  --dry-run              Print the curl command and exit
  --retries <n>          Retry count (default: 0)
  --retry-wait <sec>     Base wait in seconds between retries (default: 2)
  --timeout <sec>        Overall curl max time (default from config or unset)
  --connect-timeout <s>  Curl connect timeout seconds (default: 10)
  -v                     Verbose (log to stderr)
  -h                     Help

Examples:
  $0 -p my_api_dev -e /status
  $0 -p my_api_dev -e /users/123 -q '.data.name'
  $0 -p my_api_prod -m POST -e /users -d '{"name":"Jane"}'
  $0 -p my_api_prod -m PUT  -e /items/456 -f update.json
  $0 -p my_api_dev -m DELETE -e /posts/789 -v
  $0 -p my_api_dev -e /data -H 'X-Custom-Header: my-value'
  $0 -p my_api_dev -e /status --dry-run -v
EOF
}

# --------------------------- Globals -----------------------------------

declare -A CFG          # active profile config (flattened)
CUSTOM_HEADERS=()       # -H headers
VERBOSE="false"
DRY_RUN="false"
RETRIES=0
RETRY_WAIT=2
METHOD="GET"
CONNECT_TIMEOUT=10
TIMEOUT=""              # optional max-time
PROFILE=""
ENDPOINT=""
DATA=""
DATA_FILE=""
JQ_QUERY=""
OUT_FILE=""
RAW_OUT_FILE=""
LOG_FILE=""
CONFIG_FILE="${HOME}/.api_util.conf"

# Cleanup hook
cleanup() {
  log "Script finished."
}
trap cleanup EXIT

# --------------------------- Config Loader ------------------------------
# INI format:
# [profile]
# key = "value"
# ; comments or # comments
# base_url, auth_method (env|pass), api_key_source, auth_header_name,
# timeout (curl max time), connect_timeout, etc.

load_profile_config() {
  local profile="$1" file="$2"
  [[ -f "$file" ]] || die "Config file not found: $file"

  local in_section="false"
  while IFS= read -r line || [[ -n "$line" ]]; do
    # strip comments
    line="${line%%;*}"; line="${line%%#*}"
    # trim
    line="$(echo -n "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
      # section
      if [[ "${BASH_REMATCH[1]}" == "$profile" ]]; then
        in_section="true"
      else
        in_section="false"
      fi
      continue
    fi

    if [[ "$in_section" == "true" && "$line" =~ ^([^=]+)=(.+)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      key="$(echo -n "$key" | xargs)"
      # strip optional quotes around value
      val="$(echo -n "$val" | sed -e 's/^[[:space:]]*"\{0,1\}//' -e 's/"\{0,1\}[[:space:]]*$//')"
      CFG["$key"]="$val"
    fi
  done < "$file"

  [[ -n "${CFG[base_url]}" ]] || die "Profile '$profile' missing 'base_url' in $file"

  log "Loaded profile '$profile' from $file"
}

# --------------------------- Auth --------------------------------------

get_api_key() {
  local method="${CFG[auth_method]}"
  local source="${CFG[api_key_source]}"

  [[ -z "$method" ]] && return 0  # auth optional

  case "$method" in
    env)
      [[ -n "$source" ]] || die "auth_method=env requires api_key_source=<ENV_VAR>"
      local val="${!source}"
      [[ -n "$val" ]] || die "Environment variable '$source' is not set"
      printf "%s" "$val"
      ;;
    pass)
      command -v pass >/dev/null || die "'pass' not found. Install it to use auth_method=pass"
      [[ -n "$source" ]] || die "auth_method=pass requires api_key_source=<pass/path>"
      pass "$source" | head -n1
      ;;
    *)
      die "Unsupported auth_method: $method (use 'env' or 'pass')"
      ;;
  esac
}

# --------------------------- Curl Command Builder -----------------------

build_curl_cmd() {
  local -n _arr=$1  # name reference to return array by ref
  _arr=()

  local base="${CFG[base_url]%/}"
  local ep="$ENDPOINT"
  [[ "$ep" == /* ]] || ep="/$ep"
  local url="${base}${ep}"

  _arr+=(curl -sS)                   # silent, show errors
  _arr+=(-X "$METHOD")
  _arr+=(--connect-timeout "${CONNECT_TIMEOUT}")

  # overall timeout (optional)
  if [[ -n "$TIMEOUT" ]]; then
    _arr+=(--max-time "$TIMEOUT")
  elif [[ -n "${CFG[timeout]}" ]]; then
    _arr+=(--max-time "${CFG[timeout]}")
  fi

  # Auth header
  if [[ -n "${CFG[auth_method]}" ]]; then
    local key; key="$(get_api_key)"
    local name="${CFG[auth_header_name]:-Authorization: Bearer}"
    # name may contain a space (e.g. "Authorization: Bearer"), we append the key after it
    _arr+=(-H "$name $key")
  fi

  # Standard JSON headers
  _arr+=(-H "Accept: application/json")
  _arr+=(-H "Content-Type: application/json")

  # Custom headers
  for h in "${CUSTOM_HEADERS[@]}"; do
    _arr+=(-H "$h")
  done

  # Data (for POST/PUT/PATCH)
  case "$METHOD" in
    POST|PUT|PATCH)
      if [[ -n "$DATA" ]]; then
        _arr+=(-d "$DATA")
      elif [[ -n "$DATA_FILE" ]]; then
        [[ -f "$DATA_FILE" ]] || die "Data file not found: $DATA_FILE"
        _arr+=(-d @"$DATA_FILE")
      fi
      ;;
  esac

  _arr+=("$url")
}

# --------------------------- Request/Retry ------------------------------

should_retry_http() {
  # retry on 429 and 5xx
  local code="$1"
  [[ "$code" == "429" || ( "$code" -ge 500 && "$code" -le 599 ) ]]
}

make_request_once() {
  # Build command
  local cmd=()
  build_curl_cmd cmd

  # Dry run: print and exit success
  if [[ "$DRY_RUN" == "true" ]]; then
    printf "DRY-RUN curl command:\n"
    printf '  %q' "${cmd[@]}"; printf "\n"
    return 0
  fi

  log "Executing request:"
  log "  ${cmd[*]}"

  # We need body and status code together, even if curl errors; don't exit the script here
  set +e
  local resp; resp="$("${cmd[@]}" -w $'\n%{http_code}')"   # body\nCODE
  local rc=$?
  set -e

  if (( rc != 0 )); then
    echo "__CURL_NETWORK_ERROR__"  # special flag for the caller
    return $rc
  fi

  printf "%s" "$resp"
  return 0
}

request_with_retries() {
  local attempts=$(( RETRIES + 1 ))
  local try=1
  local wait="$RETRY_WAIT"

  while (( try <= attempts )); do
    local out; out="$(make_request_once)"
    local rc=$?

    if (( rc != 0 )); then
      log "Network error (rc=$rc) on attempt $try/$attempts"
    else
      # split body and code
      local http_code body
      http_code="$(printf "%s" "$out" | tail -n1)"
      body="$(printf "%s" "$out" | sed '$d')"

      # optional request/response log
      if [[ -n "$LOG_FILE" ]]; then
        {
          echo "===== $(date +'%Y-%m-%dT%H:%M:%S%z') ====="
          echo "REQUEST:"
          local c=(); build_curl_cmd c; printf '  %q' "${c[@]}"; printf "\n"
          echo "RESPONSE CODE: $http_code"
          echo "RESPONSE BODY:"
          printf "%s\n" "$body"
          echo
        } >> "$LOG_FILE"
      fi

      if [[ "$http_code" =~ ^[0-9]+$ ]] && (( http_code >= 200 && http_code < 300 )); then
        # success
        printf "%s" "$body"
        return 0
      fi

      # If HTTP error and eligible for retry
      if should_retry_http "$http_code"; then
        log "HTTP $http_code — will retry attempt $try/$attempts"
      else
        # hard fail (non-retryable)
        printf "%s" "$body" > /dev/null  # no-op; body already captured
        printf "%s" "$http_code" > /dev/null
        printf "%s" "$body" > /tmp/api_last_body.$$ 2>/dev/null || true
        die "API request failed with status code $http_code.
Tip: run with -v or set -L <logfile> to capture full details."
      fi
    fi

    # If more tries left, backoff
    if (( try < attempts )); then
      log "Sleeping ${wait}s before retry..."
      sleep "$wait"
      wait=$(( wait * 2 ))
    fi
    ((try++))
  done

  die "Request failed after $RETRIES retries."
}

main() {
  # parse args
  while (( $# )); do
    case "$1" in
      -c) CONFIG_FILE="$2"; shift 2 ;;
      -p) PROFILE="$2"; shift 2 ;;
      -m) METHOD="$2"; shift 2 ;;
      -e) ENDPOINT="$2"; shift 2 ;;
      -d) DATA="$2"; shift 2 ;;
      -f) DATA_FILE="$2"; shift 2 ;;
      -H) CUSTOM_HEADERS+=("$2"); shift 2 ;;
      -q) JQ_QUERY="$2"; shift 2 ;;
      -o) OUT_FILE="$2"; shift 2 ;;
      -O) RAW_OUT_FILE="$2"; shift 2 ;;
      -L) LOG_FILE="$2"; shift 2 ;;
      --dry-run) DRY_RUN="true"; shift ;;
      --retries) RETRIES="$2"; shift 2 ;;
      --retry-wait) RETRY_WAIT="$2"; shift 2 ;;
      --timeout) TIMEOUT="$2"; shift 2 ;;
      --connect-timeout) CONNECT_TIMEOUT="$2"; shift 2 ;;
      -v) VERBOSE="true"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (use -h for help)" ;;
    esac
  done

  # validations
  command -v curl >/dev/null || die "'curl' is required but not installed."
  command -v jq   >/dev/null || die "'jq' is required but not installed."

  [[ -n "$PROFILE"   ]] || die "Missing -p <profile>"
  [[ -n "$ENDPOINT"  ]] || die "Missing -e <endpoint>"

  METHOD="$(echo "$METHOD" | tr '[:lower:]' '[:upper:]')"
  case "$METHOD" in GET|POST|PUT|PATCH|DELETE) ;; *) die "Unsupported method: $METHOD" ;; esac

  if [[ -n "$DATA" && -n "$DATA_FILE" ]]; then
    die "Provide either -d <data> or -f <file>, not both."
  fi

  # load profile
  load_profile_config "$PROFILE" "$CONFIG_FILE"

  # perform request (with retries/backoff)
  local body; body="$(request_with_retries)"

  # optionally save raw body
  if [[ -n "$RAW_OUT_FILE" ]]; then
    printf "%s" "$body" > "$RAW_OUT_FILE"
    log "Raw response written to: $RAW_OUT_FILE"
  fi

  # pretty print or query
  if [[ -n "$JQ_QUERY" ]]; then
    log "Applying jq query: $JQ_QUERY"
    if ! jq -r "$JQ_QUERY" <<< "$body"; then
      die "jq query failed. Check your query syntax."
    fi | { if [[ -n "$OUT_FILE" ]]; then tee "$OUT_FILE"; else cat; fi; }
  else
    # pretty print JSON
    if ! jq '.' <<< "$body"; then
      die "Response is not valid JSON (or jq failed)."
    fi | { if [[ -n "$OUT_FILE" ]]; then tee "$OUT_FILE"; else cat; fi; }
  fi
}

# Enable errexit only after function defs to keep control inside functions
set -e
main "$@"
