#!/usr/bin/env bash
# symmetric GPG encryption/decryption

set -euo pipefail
IFS=$'\n\t'

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="$HOME/.encrypt_file.log"
MAX_LOG_SIZE=$((1024*1024))

usage() {
  cat <<EOF
Usage: $0 -i input -o output [-p passphrase] [-c compression] [-b] [-d]
  -i input        : input file to encrypt/decrypt
  -o output       : output file name
  -p passphrase   : passphrase (if omitted, prompted securely)
  -c compression  : compression level 0-9 (default: 6, only applies to encryption)
  -b              : backup existing output file
  -d              : decrypt instead of encrypt

Examples:
  Encrypt: $0 -i file.txt -o file.gpg -c 9 -b
  Decrypt: $0 -i file.gpg -o file.txt -d
EOF
  exit 1
}

check_passphrase_strength() {
  local pass=$1
  local min_length=12
  [[ ${#pass} -ge $min_length ]] || {
    echo -e "${RED}Passphrase too short (minimum $min_length characters)${NC}" >&2
    return 1
  }
  [[ $pass =~ [A-Z] ]] || {
    echo -e "${RED}Must contain at least one uppercase letter${NC}" >&2
    return 1
  }
  [[ $pass =~ [a-z] ]] || {
    echo -e "${RED}Must contain at least one lowercase letter${NC}" >&2
    return 1
  }
  [[ $pass =~ [0-9] ]] || {
    echo -e "${RED}Must contain at least one number${NC}" >&2
    return 1
  }
  [[ $pass =~ [^A-Za-z0-9] ]] || {
    echo -e "${RED}Must contain at least one special character${NC}" >&2
    return 1
  }
}

rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if (( size > MAX_LOG_SIZE )); then
      mv "$LOG_FILE" "${LOG_FILE}.$(date -u +%s).bak"
    fi
  fi
}

log_message() {
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  echo "[$timestamp] $1" >> "$LOG_FILE"
}

# Default values
in=""
out=""
pass=""
compression=6
backup=false
decrypt=false

# Parse options
while getopts ":i:o:p:c:bd" opt; do
  case $opt in
    i) in=$OPTARG ;;
    o) out=$OPTARG ;;
    p) pass=$OPTARG ;;
    c) compression=$OPTARG ;;
    b) backup=true ;;
    d) decrypt=true ;;
    *) usage ;;
  esac
done

# Validate inputs
[[ -f $in ]] || { echo -e "${RED}Input file not found: $in${NC}" >&2; log_message "Error: Input file not found: $in"; exit 1; }
[[ -n $out ]] || { echo -e "${RED}Output file not specified${NC}" >&2; log_message "Error: Output file not specified"; usage; }
[[ $out != "$in" ]] || { echo -e "${RED}Input and output files cannot be the same${NC}" >&2; log_message "Error: Input and output files cannot be the same"; exit 1; }

# Check for GPG
if ! command -v gpg >/dev/null; then
  echo -e "${RED}GPG not installed${NC}" >&2
  log_message "Error: GPG not installed"
  exit 1
fi

# Prompt for passphrase
if [[ -z $pass ]]; then
  read -rsp "${GREEN}Enter passphrase: ${NC}" pass
  echo
  if [[ $decrypt == false ]]; then
    read -rsp "${GREEN}Confirm passphrase: ${NC}" pass2
    echo
    [[ $pass == $pass2 ]] || { echo -e "${RED}Passphrases do not match${NC}" >&2; log_message "Error: Passphrases do not match"; exit 1; }
  fi
fi

# Validate passphrase (only on encryption)
if [[ $decrypt == false ]]; then
  [[ $compression =~ ^[0-9]$ ]] || {
    echo -e "${RED}Invalid compression level (0-9)${NC}" >&2
    log_message "Error: Invalid compression level: $compression"
    exit 1
  }
  check_passphrase_strength "$pass" || { log_message "Error: Weak passphrase"; exit 1; }
fi

# Rotate log
rotate_log

# Handle existing output
if [[ -f $out && $backup == true ]]; then
  mv "$out" "${out}.$(date -u +%s).bak"
  log_message "Backed up existing output file to ${out}.$(date -u +%s).bak"
fi

# Main operation
if [[ $decrypt == true ]]; then
  echo -e "${BLUE}Decrypting $in to $out...${NC}"
  log_message "Starting decryption of $in to $out"

  if gpg --batch --yes --decrypt --passphrase "$pass" -o "$out" "$in" 2> >(grep -v '^$' >&2); then
    echo -e "${GREEN}Successfully decrypted $in → $out${NC}"
    log_message "Successfully decrypted $in to $out"
  else
    echo -e "${RED}Decryption failed${NC}" >&2
    log_message "Error: Decryption failed for $in"
    exit 1
  fi
else
  echo -e "${BLUE}Encrypting $in to $out...${NC}"
  log_message "Starting encryption of $in to $out with compression level $compression"

  if gpg --batch --yes --symmetric --cipher-algo AES256 \
      --compress-algo zip --compress-level "$compression" \
      --passphrase "$pass" -o "$out" "$in" 2> >(grep -v '^$' >&2); then
    echo -e "${GREEN}Successfully encrypted $in → $out${NC}"
    log_message "Successfully encrypted $in to $out"
  else
    echo -e "${RED}Encryption failed${NC}" >&2
    log_message "Error: Encryption failed for $in"
    exit 1
  fi
fi
