#!/usr/bin/env bash
# interactive_menu.sh – Enhanced interactive toolkit menu

set -euo pipefail
IFS=$'\n\t'

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration and history files
CONFIG_FILE="$HOME/.toolkit_menu.conf"
HISTORY_FILE="$HOME/.toolkit_menu_history"
SCRIPTS_DIR="$HOME/toolkit_scripts"  # Default directory for scripts

# Create history file if it doesn't exist
touch "$HISTORY_FILE"

# Load config file if exists
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"

# Default values
DEFAULT_SUBNET="${DEFAULT_SUBNET:-192.168.1.0/24}"
DEFAULT_PORTS="${DEFAULT_PORTS:-22,80,443}"
DEFAULT_FORMAT="${DEFAULT_FORMAT:-json}"
DEFAULT_OUTDIR="${DEFAULT_OUTDIR:-/tmp}"

usage() {
  cat <<EOF
Usage: $0 [-c config_file] [-n]
  -c config_file : specify custom config file (default: $CONFIG_FILE)
  -n             : non-interactive mode with default values
EOF
  exit 1
}

menu() {
  cat <<EOF
${BLUE}==== TOOLKIT MENU ====${NC}
1) Network scan
2) File encryption
3) Auto deploy
4) Exit
EOF
}

# Generic validation function
validate_input() {
  local input=$1
  local type=$2
  local error_msg=$3
  case $type in
    subnet) [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1 ;;
    ports) [[ $input =~ ^[0-9,-]+$ ]] || return 1 ;;
    file) [[ -f $input ]] || return 1 ;;
    target) [[ $input =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || return 1 ;;
    *) return 1 ;;
  esac
  return 0
}

read_choice() {
  read -rp "${GREEN}Select an option [1-4]: ${NC}" choice
  [[ $choice =~ ^[1-4]$ ]] || {
    echo -e "${RED}Invalid choice${NC}"
    return 1
  }
  echo "$choice" >> "$HISTORY_FILE"
}

do_network() {
  local subnet ports format
  if [[ "$non_interactive" == true ]]; then
    subnet="$DEFAULT_SUBNET"
    ports="$DEFAULT_PORTS"
    format="$DEFAULT_FORMAT"
  else
    read -rp "${GREEN}Subnet (default: $DEFAULT_SUBNET): ${NC}" subnet
    subnet=${subnet:-$DEFAULT_SUBNET}
    validate_input "$subnet" subnet "Invalid subnet format" || return 1
    read -rp "${GREEN}Ports (default: $DEFAULT_PORTS): ${NC}" ports
    ports=${ports:-$DEFAULT_PORTS}
    validate_input "$ports" ports "Invalid ports format" || return 1
    read -rp "${GREEN}Output format (json/csv, default: $DEFAULT_FORMAT): ${NC}" format
    format=${format:-$DEFAULT_FORMAT}
    [[ $format == "json" || $format == "csv" ]] || {
      echo -e "${RED}Invalid format${NC}" >&2
      return 1
    }
  fi

  echo -e "${BLUE}Running network scan...${NC}"
  if ! "$SCRIPTS_DIR/network_scanner.sh" -s "$subnet" -p "$ports" -o "$format"; then
    echo -e "${RED}Network scan failed${NC}" >&2
    return 1
  fi
  echo -e "${GREEN}Network scan completed${NC}"
  echo "network_scan: $subnet $ports $format" >> "$HISTORY_FILE"
}

do_encrypt() {
  local file out pass
  if [[ "$non_interactive" == true ]]; then
    echo -e "${RED}Encryption requires interactive input for security${NC}" >&2
    return 1
  fi

  read -rp "${GREEN}File to encrypt: ${NC}" file
  validate_input "$file" file "File not found" || return 1

  read -rp "${GREEN}Output encrypted file (default: $DEFAULT_OUTDIR/$(basename "$file").enc): ${NC}" out
  out=${out:-$DEFAULT_OUTDIR/$(basename "$file").enc}

  read -rsp "${GREEN}Passphrase: ${NC}" pass
  echo
  [[ -n $pass ]] || {
    echo -e "${RED}Passphrase cannot be empty${NC}" >&2
    return 1
  }

  echo -e "${BLUE}Encrypting file...${NC}"
  if ! "$SCRIPTS_DIR/encrypt_file.sh" -i "$file" -o "$out" -p "$pass"; then
    echo -e "${RED}File encryption failed${NC}" >&2
    return 1
  fi
  echo -e "${GREEN}File encryption completed${NC}"
  echo "encrypt: $file $out" >> "$HISTORY_FILE"
}

do_deploy() {
  local script target dest
  if [[ "$non_interactive" == true ]]; then
    echo -e "${RED}Deployment requires interactive input${NC}" >&2
    return 1
  fi

  read -rp "${GREEN}Deployment script path: ${NC}" script
  validate_input "$script" file "Script file not found" || return 1

  read -rp "${GREEN}Target server (user@host): ${NC}" target
  validate_input "$target" target "Invalid target format" || return 1

  read -rp "${GREEN}Remote directory: ${NC}" dest
  [[ -n $dest ]] || {
    echo -e "${RED}Remote directory cannot be empty${NC}" >&2
    return 1
  }

  echo -e "${BLUE}Running deployment...${NC}"
  if ! "$SCRIPTS_DIR/auto_deploy.sh" -s "$script" -t "$target" -d "$dest"; then
    echo -e "${RED}Deployment failed${NC}" >&2
    return 1
  fi
  echo -e "${GREEN}Deployment completed${NC}"
  echo "deploy: $script $target $dest" >> "$HISTORY_FILE"
}

non_interactive=false
while getopts ":c:n" opt; do
  case $opt in
    c) CONFIG_FILE=$OPTARG ;;
    n) non_interactive=true ;;
    *) usage ;;
  esac
done

# Check for required scripts in the SCRIPTS_DIR
for script in network_scanner.sh encrypt_file.sh auto_deploy.sh; do
  if [[ ! -x "$SCRIPTS_DIR/$script" ]]; then
    echo -e "${RED}Required script $script not found or not executable in $SCRIPTS_DIR${NC}" >&2
    exit 1
  fi
done

while true; do
  menu
  if ! read_choice; then
    echo
    continue
  fi
  case $choice in
    1) do_network ;;
    2) do_encrypt ;;
    3) do_deploy ;;
    4) echo -e "${BLUE}Exiting toolkit${NC}"; exit 0 ;;
  esac
