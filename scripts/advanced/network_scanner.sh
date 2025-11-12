#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

DEFAULT_PORTS="1-1024"
DEFAULT_FORMAT="json"
MAX_LOG_SIZE=$((1024*1024))
MAX_THREADS=64
DEFAULT_THREADS=4
NMAP_TIMEOUT="15s"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' 
log_message() {
  local message="$1"
  local logfile="${2:-}" 
  echo -e "$message" >&2
  if [[ -n "$logfile" ]]; then
    echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ"): $(echo -e "$message" | sed 's/\x1B\[[0-9;]*[a-zA-Z]//g')" >> "$logfile"
  fi
}

usage() {
  cat <<EOF
${GREEN}Network Scanner${NC} - Advanced host and port scanning tool

${BLUE}Usage:${NC} $0 [-s subnet] [-p ports] [-o json|csv] [-l logfile] [-t threads] [-v]
  ${YELLOW}-s subnet${NC}    : Target subnet in CIDR (e.g., 192.168.1.0/24). Default: auto-detect local LAN.
  ${YELLOW}-p ports${NC}     : Ports to scan (e.g., "22,80,443", "1-1024"). Default: ${DEFAULT_PORTS}.
  ${YELLOW}-o format${NC}    : Output format (json|csv). Default: ${DEFAULT_FORMAT}.
  ${YELLOW}-l logfile${NC}   : Log file path. Enables logging and log rotation.
  ${YELLOW}-t threads${NC}   : Number of parallel threads (1-${MAX_THREADS}). Default: ${DEFAULT_THREADS}.
  ${YELLOW}-v${NC}           : Verbose mode. Shows the exact nmap command and detailed progress.

${BLUE}Examples:${NC}
  # Scan local network for common ports with verbose output
  $0 -v

  # Scan a specific subnet for high ports, using 16 threads
  $0 -s 10.0.0.0/24 -p 8000-9000 -t 16

  # Save results to a CSV file and log activity
  $0 -o csv -l /var/log/scan.log

${RED}Note:${NC} Requires 'nmap'. Running with 'sudo' is recommended for faster, more accurate SYN scans.
EOF
  exit 1
}

get_local_subnet() {
  ip -o -f inet route get 1.1.1.1 2>/dev/null | awk '{print $7}' | while read -r ip; do
    ipcalc -np "$ip" 2>/dev/null | grep ^Network: | awk '{print $2}' && return
  done
  ip -o -f inet addr show scope global | awk '{print $4}' | head -n1
}

validate_subnet() {
  local subnet=$1
  if [[ ! $subnet =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_message "${RED}Error: Invalid subnet format '${subnet}'. Use CIDR notation (e.g., 192.168.1.0/24).${NC}" "$logfile"
    exit 1
  fi
}

validate_ports() {
  local ports=$1
  if [[ ! $ports =~ ^[0-9,-]+$ ]]; then
    log_message "${RED}Error: Invalid ports format '${ports}'. Use comma-separated values or ranges.${NC}" "$logfile"
    exit 1
  fi
}

validate_threads() {
  local threads=$1
  if [[ ! $threads =~ ^[0-9]+$ ]] || (( threads < 1 || threads > MAX_THREADS )); then
    log_message "${RED}Error: Threads must be a number between 1 and ${MAX_THREADS}.${NC}" "$logfile"
    exit 1
  fi
}

rotate_log() {
  local logfile_path=$1
  if [[ -f "$logfile_path" ]]; then
    local size
    size=$(stat -f%z "$logfile_path" 2>/dev/null || stat -c%s "$logfile_path" 2>/dev/null || echo 0)
    if (( size > MAX_LOG_SIZE )); then
      log_message "${BLUE}Rotating log file ${logfile_path}${NC}" "$logfile_path"
      mv "$logfile_path" "${logfile_path}.$(date -u +%Y%m%d_%H%M%S).bak"
    fi
  fi
}

#mainstuff
subnet=""
ports="$DEFAULT_PORTS"
format="$DEFAULT_FORMAT"
logfile=""
threads="$DEFAULT_THREADS"
verbose=0

while getopts ":s:p:o:l:t:v" opt; do
  case $opt in
    s) subnet=$OPTARG ;;
    p) ports=$OPTARG ;;
    o) format=$OPTARG ;;
    l) logfile=$OPTARG ;;
    t) threads=$OPTARG ;;
    v) verbose=1 ;;
    \?) log_message "${RED}Invalid option: -$OPTARG${NC}"; usage ;;
    :) log_message "${RED}Option -$OPTARG requires an argument.${NC}"; usage ;;
  esac
done

if [[ -z "$subnet" ]]; then
  subnet=$(get_local_subnet)
  if [[ -z "$subnet" ]]; then
    log_message "${RED}Error: Could not automatically determine local subnet. Please specify one with -s.${NC}" "$logfile"
    exit 1
  fi
  log_message "${YELLOW}Auto-detected subnet: ${subnet}${NC}" "$logfile"
fi

validate_subnet "$subnet"
validate_ports "$ports"
validate_threads "$threads"
if [[ "$format" != "json" && "$format" != "csv" ]]; then
  log_message "${RED}Error: Invalid format '${format}'. Use 'json' or 'csv'.${NC}" "$logfile"
  exit 1
fi

if ! command -v nmap >/dev/null; then
  log_message "${RED}Error: 'nmap' is required but not installed. Please install it to continue.${NC}" "$logfile"
  exit 1
fi

[[ -n "$logfile" ]] && rotate_log "$logfile"

tmp_file=$(mktemp /tmp/nmap_scan.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT

log_message "${GREEN}Starting network scan...${NC}" "$logfile"
log_message "  - Subnet:        ${BLUE}${subnet}${NC}"
log_message "  - Ports:         ${BLUE}${ports}${NC}"
log_message "  - Threads:       ${BLUE}${threads}${NC}"
log_message "  - Output Format: ${BLUE}${format}${NC}"
[[ -n "$logfile" ]] && log_message "  - Log File:      ${BLUE}${logfile}${NC}"

nmap_args=(
  -p "$ports"
  -T4 
  --min-rate 1000
  --max-retries 1
  --host-timeout "$NMAP_TIMEOUT"
  --min-parallelism "$threads"
  --max-parallelism "$threads"
  -oG "$tmp_file"
  --open
  "$subnet"
)

if [[ $EUID -eq 0 ]]; then
  log_message "${GREEN}Running with root privileges. Using faster SYN scan (-sS).${NC}" "$logfile"
  nmap_args=("-sS" "${nmap_args[@]}")
else
  log_message "${YELLOW}Warning: Not running as root. Using default TCP connect scan. For faster results, run with 'sudo'.${NC}" "$logfile"
fi

if (( verbose == 0 )); then
  nmap_args+=("--stats-every" "10s")
else
  printf "${BLUE}Executing command:${NC} nmap %s\n" "${nmap_args[*]}" >&2
fi

start_time=$(date +%s)
log_message "${YELLOW}Scanning network... This may take a while.${NC}" "$logfile"

if ! nmap "${nmap_args[@]}"; then
    log_message "${RED}Nmap scan failed. Check permissions, network connectivity, or nmap arguments.${NC}" "$logfile"
    exit 1
fi

end_time=$(date +%s)
duration=$((end_time - start_time))


log_message "\n${GREEN}Scan complete in ${duration} seconds. Processing results...${NC}" "$logfile"

if [[ ! -s "$tmp_file" ]]; then
    log_message "${YELLOW}No hosts with open ports were found.${NC}" "$logfile"
    exit 0
fi

declare -A hosts
while IFS= read -r line; do
    [[ "$line" == "#"* ]] && continue

    if [[ "$line" =~ Host:\ ([0-9.]+) \(([^)]*)\)\s+Ports:\ (.*) ]]; then
        ip="${BASH_REMATCH[1]}"
        portsinfo="${BASH_REMATCH[3]}"

        port_list=()
        for protoport in ${portsinfo//, / }; do
            portnum=$(echo "$protoport" | cut -d'/' -f1)
            service=$(echo "$protoport" | cut -d'/' -f5)
            [[ -z "$service" ]] && service="unknown"
            port_list+=("$portnum/$service")
        done

        if (( ${#port_list[@]} > 0 )); then
            hosts["$ip"]=$(IFS=,; echo "${port_list[*]}")
        fi
    fi
done < "$tmp_file"


if (( ${#hosts[@]} == 0 )); then
  log_message "${YELLOW}No hosts with open ports were found.${NC}" "$logfile"
  exit 0
fi

log_message "${GREEN}Found ${#hosts[@]} host(s) with open ports:${NC}" "$logfile"

if [[ "$format" == "csv" ]]; then
  echo '"IP Address","Port","Service"'
  for ip in "${!hosts[@]}"; do
    IFS=',' read -r -a port_array <<< "${hosts[$ip]}"
    for port_svc in "${port_array[@]}"; do
        port="${port_svc%/*}"
        service="${port_svc#*/}"
        echo "\"$ip\",\"$port\",\"$service\""
    done
  done
elif [[ "$format" == "json" ]]; then
  output="["
  first_host=true
  for ip in "${!hosts[@]}"; do
    if ! $first_host; then
      output+=","
    fi
    first_host=false
    output+="\n  {\n    \"ip\": \"$ip\",\n    \"ports\": ["
    
    IFS=',' read -r -a port_array <<< "${hosts[$ip]}"
    first_port=true
    for port_svc in "${port_array[@]}"; do
        if ! $first_port; then
          output+=","
        fi
        first_port=false
        port="${port_svc%/*}"
        service="${port_svc#*/}"
        service_escaped=${service//\"/\\\"}
        output+="\n      {\n        \"port\": $port,\n        \"service\": \"$service_escaped\"\n      }"
    done
    output+="\n    ]\n  }"
  done
  output+="\n]"
  echo -e "$output"
fi
