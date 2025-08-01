#!/usr/bin/env bash

# This script performs comprehensive network scanning using nmap to discover open ports and services across a subnet, with formatted output and logging.
#
# Key Features:
#
#    Scans specified ports across all hosts in a subnet
#    Supports JSON/CSV output formats
#    Progress tracking during scans
#    Thread control for parallel scanning
#    Log rotation and verbose modes
#    Automatic local subnet detection
#
# Usage: ./network_scanner_v2.sh -s <subnet> -p <ports> -o <output_format> -l <logfile> -t <threads> [-v]

set -euo pipefail
# Set IFS to newline and tab only. Important for loops over file names/paths.
IFS=$'\n\t'

# --- Configuration ---
DEFAULT_PORTS="1-1024"
DEFAULT_FORMAT="json"
MAX_LOG_SIZE=$((1024*1024))
MAX_THREADS=64
DEFAULT_THREADS=4
NMAP_TIMEOUT="15s" # nmap's --host-timeout format

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Functions ---
log_message() {
  local message="$1"
  local logfile="${2:-}" # Optional second argument for log file path
  echo -e "$message" >&2
  if [[ -n "$logfile" ]]; then
    # Strip color codes before writing to log
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

# Use `ip route` which is often more reliable for finding the primary outbound interface
get_local_subnet() {
  ip -o -f inet route get 1.1.1.1 2>/dev/null | awk '{print $7}' | while read -r ip; do
    ipcalc -np "$ip" 2>/dev/null | grep ^Network: | awk '{print $2}' && return
  done
  # Fallback to original method if ipcalc isn't available or the above fails
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
  # Allow digits, comma, and hyphen. Basic validation.
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
    # Works on both macOS (stat -f%z) and Linux (stat -c%s)
    local size
    size=$(stat -f%z "$logfile_path" 2>/dev/null || stat -c%s "$logfile_path" 2>/dev/null || echo 0)
    if (( size > MAX_LOG_SIZE )); then
      log_message "${BLUE}Rotating log file ${logfile_path}${NC}" "$logfile_path"
      mv "$logfile_path" "${logfile_path}.$(date -u +%Y%m%d_%H%M%S).bak"
    fi
  fi
}


# --- Main Script ---

# Initialize variables
subnet=""
ports="$DEFAULT_PORTS"
format="$DEFAULT_FORMAT"
logfile=""
threads="$DEFAULT_THREADS"
verbose=0

# Parse command line arguments
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

# Set default subnet if not provided
if [[ -z "$subnet" ]]; then
  subnet=$(get_local_subnet)
  if [[ -z "$subnet" ]]; then
    log_message "${RED}Error: Could not automatically determine local subnet. Please specify one with -s.${NC}" "$logfile"
    exit 1
  fi
  log_message "${YELLOW}Auto-detected subnet: ${subnet}${NC}" "$logfile"
fi

# Validate inputs
validate_subnet "$subnet"
validate_ports "$ports"
validate_threads "$threads"
if [[ "$format" != "json" && "$format" != "csv" ]]; then
  log_message "${RED}Error: Invalid format '${format}'. Use 'json' or 'csv'.${NC}" "$logfile"
  exit 1
fi

# Check for required tools
if ! command -v nmap >/dev/null; then
  log_message "${RED}Error: 'nmap' is required but not installed. Please install it to continue.${NC}" "$logfile"
  exit 1
fi

# Handle logging setup
[[ -n "$logfile" ]] && rotate_log "$logfile"

# Setup temporary file for nmap output and ensure it's cleaned up
tmp_file=$(mktemp /tmp/nmap_scan.XXXXXX)
trap 'rm -f "$tmp_file"' EXIT

# --- Build and Execute Nmap Command ---

log_message "${GREEN}Starting network scan...${NC}" "$logfile"
log_message "  - Subnet:        ${BLUE}${subnet}${NC}"
log_message "  - Ports:         ${BLUE}${ports}${NC}"
log_message "  - Threads:       ${BLUE}${threads}${NC}"
log_message "  - Output Format: ${BLUE}${format}${NC}"
[[ -n "$logfile" ]] && log_message "  - Log File:      ${BLUE}${logfile}${NC}"

nmap_args=(
  -p "$ports"
  -T4 # Aggressive timing template
  --min-rate 1000 # Scan faster on good networks
  --max-retries 1
  --host-timeout "$NMAP_TIMEOUT"
  --min-parallelism "$threads"
  --max-parallelism "$threads"
  -oG "$tmp_file" # Greppable output for easy parsing
  --open # Only show hosts with open ports
  "$subnet"
)

# Use faster SYN scan if root, otherwise nmap defaults to TCP connect scan
if [[ $EUID -eq 0 ]]; then
  log_message "${GREEN}Running with root privileges. Using faster SYN scan (-sS).${NC}" "$logfile"
  nmap_args=("-sS" "${nmap_args[@]}")
else
  log_message "${YELLOW}Warning: Not running as root. Using default TCP connect scan. For faster results, run with 'sudo'.${NC}" "$logfile"
fi

# Add progress reporting if not in verbose mode (to avoid clutter)
if (( verbose == 0 )); then
  nmap_args+=("--stats-every" "10s")
else
  # In verbose mode, print the full command for debugging
  printf "${BLUE}Executing command:${NC} nmap %s\n" "${nmap_args[*]}" >&2
fi

# Execute nmap
start_time=$(date +%s)
log_message "${YELLOW}Scanning network... This may take a while.${NC}" "$logfile"

if ! nmap "${nmap_args[@]}"; then
    log_message "${RED}Nmap scan failed. Check permissions, network connectivity, or nmap arguments.${NC}" "$logfile"
    exit 1
fi

end_time=$(date +%s)
duration=$((end_time - start_time))

# --- Parse and Format Results ---

log_message "\n${GREEN}Scan complete in ${duration} seconds. Processing results...${NC}" "$logfile"

# Check if the output file has any results
if [[ ! -s "$tmp_file" ]]; then
    log_message "${YELLOW}No hosts with open ports were found.${NC}" "$logfile"
    exit 0
fi

# Using an associative array to store results: hosts[ip]="port/svc,port/svc"
declare -A hosts
while IFS= read -r line; do
    # Skip comments and header
    [[ "$line" == "#"* ]] && continue

    # Extract IP and port info using regex
    if [[ "$line" =~ Host:\ ([0-9.]+) \(([^)]*)\)\s+Ports:\ (.*) ]]; then
        ip="${BASH_REMATCH[1]}"
        # hostname="${BASH_REMATCH[2]}" # Hostname is available if needed
        portsinfo="${BASH_REMATCH[3]}"

        port_list=()
        # Process each port entry
        for protoport in ${portsinfo//, / }; do
            # Format: 22/open/tcp//ssh///
            portnum=$(echo "$protoport" | cut -d'/' -f1)
            service=$(echo "$protoport" | cut -d'/' -f5)
            # If service name is empty, use 'unknown'
            [[ -z "$service" ]] && service="unknown"
            port_list+=("$portnum/$service")
        done

        if (( ${#port_list[@]} > 0 )); then
            hosts["$ip"]=$(IFS=,; echo "${port_list[*]}")
        fi
    fi
done < "$tmp_file"

# --- Generate Final Output ---

if (( ${#hosts[@]} == 0 )); then
  log_message "${YELLOW}No hosts with open ports were found.${NC}" "$logfile"
  exit 0
fi

log_message "${GREEN}Found ${#hosts[@]} host(s) with open ports:${NC}" "$logfile"

if [[ "$format" == "csv" ]]; then
  # CSV Header
  echo '"IP Address","Port","Service"'
  for ip in "${!hosts[@]}"; do
    # Read comma-separated ports into an array
    IFS=',' read -r -a port_array <<< "${hosts[$ip]}"
    for port_svc in "${port_array[@]}"; do
        port="${port_svc%/*}"
        service="${port_svc#*/}"
        echo "\"$ip\",\"$port\",\"$service\""
    done
  done
elif [[ "$format" == "json" ]]; then
  # JSON Output
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
        # Basic JSON escaping for the service name
        service_escaped=${service//\"/\\\"}
        output+="\n      {\n        \"port\": $port,\n        \"service\": \"$service_escaped\"\n      }"
    done
    output+="\n    ]\n  }"
  done
  output+="\n]"
  echo -e "$output"
fi
