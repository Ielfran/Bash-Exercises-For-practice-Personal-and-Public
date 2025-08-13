#!/usr/bin/env bash
# sys-toolkit - Advanced system administration CLI tool

set -o errexit
set -o nounset
set -o pipefail

readonly SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
readonly VERSION="1.1.0"

declare -A CONFIG
CONFIG[log_file]="/var/log/${SCRIPT_NAME}.log"
CONFIG[cpu_warn_threshold]=80
CONFIG[mem_warn_threshold]=80
CONFIG[disk_warn_threshold]=85
CONFIG[debug]=false

# ANSI colors
readonly COLOR_RESET='\e[0m'
readonly COLOR_RED='\e[0;31m'
readonly COLOR_GREEN='\e[0;32m'
readonly COLOR_YELLOW='\e[0;33m'
readonly COLOR_BLUE='\e[0;34m'
readonly COLOR_CYAN='\e[0;36m'

trap 'echo -e "\n${COLOR_YELLOW}WARN:${COLOR_RESET} Operation cancelled by user."; exit 130;' INT

debug() {
    if [[ "${CONFIG[debug]}" == "true" ]]; then
        echo -e "${COLOR_CYAN}DEBUG:${COLOR_RESET} [$SCRIPT_NAME] $*" >&2
    fi
}

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S %Z')

    # Fallback to user logs if /var/log not writable
    if ! touch "${CONFIG[log_file]}" &>/dev/null; then
        CONFIG[log_file]="${HOME}/.local/logs/${SCRIPT_NAME}.log"
        mkdir -p "$(dirname "${CONFIG[log_file]}")"
        touch "${CONFIG[log_file]}"
    fi

    echo "${timestamp} [${level}] - ${message}" >> "${CONFIG[log_file]}"
}

printer() {
    local color="$1"
    local label="$2"
    local message="$3"
    echo -e "${color}${label}:${COLOR_RESET} ${message}" >&2
}

die() {
    local message="$1"
    local exit_code=${2:-1}
    log "ERROR" "$message"
    printer "$COLOR_RED" "FATAL" "$message"
    exit "$exit_code"
}

check_dependency() {
    command -v "$1" >/dev/null 2>&1 || die "Missing dependency: '$1'. Please install it."
}

ensure_root() {
    if [[ $EUID -ne 0 ]]; then
        printer "$COLOR_YELLOW" "NOTICE" "Root privileges required. Re-running with sudo..."
        exec sudo -E bash "$0" "$@"
    fi
}

load_config() {
    local sys_config="/etc/${SCRIPT_NAME}.conf"
    local user_config="${HOME}/.config/${SCRIPT_NAME}/config"
    local config_file=""

    if [[ -f "$sys_config" ]]; then
        config_file="$sys_config"
    elif [[ -f "$user_config" ]]; then
        config_file="$user_config"
    fi

    if [[ -n "$config_file" ]]; then
        log "INFO" "Loading config from $config_file"
        printer "$COLOR_BLUE" "INFO" "Using config: $config_file"
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^\s*# || -z "$key" ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | sed -e 's/^["]*//' -e 's/["]*$//' | xargs)
            CONFIG["$key"]="$value"
        done < <(grep -v '^\s*#' "$config_file" | grep -v '^\s*$')
    fi
}

usage_check() {
    cat <<EOF
Usage: ${SCRIPT_NAME} check [--cpu] [--mem] [--disk <path>]

Options:
  --cpu           Check CPU utilization.
  --mem           Check memory usage.
  --disk <path>   Check disk usage for a specific path.
  -h, --help      Show this help.
EOF
}

cmd_check() {
    check_dependency "bc"
    check_dependency "top"
    check_dependency "free"
    check_dependency "df"

    local check_cpu=false check_mem=false check_disk=""
    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cpu) check_cpu=true ;;
            --mem) check_mem=true ;;
            --disk) check_disk="${2:-}"; shift ;;
            -h|--help) usage_check; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
        shift
    done

    if ! $check_cpu && ! $check_mem && [[ -z "$check_disk" ]]; then
        check_cpu=true
        check_mem=true
        check_disk="/"
    fi

    log "INFO" "Running system checks"
    printer "$COLOR_BLUE" "INFO" "Performing system health checks..."

    if $check_cpu; then
        local cpu_usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}')
        printf "%-20s: %.2f%%\n" "CPU Utilization" "$cpu_usage"
        (( $(echo "$cpu_usage > ${CONFIG[cpu_warn_threshold]}" | bc -l) )) &&
            printer "$COLOR_YELLOW" "WARN" "CPU usage above ${CONFIG[cpu_warn_threshold]}%"
    fi

    if $check_mem; then
        local mem_usage
        mem_usage=$(free | awk '/Mem/ {print $3/$2 * 100.0}')
        printf "%-20s: %.2f%%\n" "Memory Usage" "$mem_usage"
        (( $(echo "$mem_usage > ${CONFIG[mem_warn_threshold]}" | bc -l) )) &&
            printer "$COLOR_YELLOW" "WARN" "Memory usage above ${CONFIG[mem_warn_threshold]}%"
    fi

    if [[ -n "$check_disk" ]]; then
        local disk_usage
        disk_usage=$(df -h "$check_disk" | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
        printf "%-20s: %d%%\n" "Disk Usage ($check_disk)" "$disk_usage"
        (( disk_usage > ${CONFIG[disk_warn_threshold]} )) &&
            printer "$COLOR_YELLOW" "WARN" "Disk usage above ${CONFIG[disk_warn_threshold]}%"
    fi
}

usage_service() {
    cat <<EOF
Usage: ${SCRIPT_NAME} service <start|stop|restart|status> <service>

Manages systemd services. Requires root.
EOF
}

cmd_service() {
    ensure_root "$@"
    check_dependency "systemctl"

    local action=${2:-} service_name=${3:-}
    [[ -z "$action" || -z "$service_name" ]] && usage_service && exit 1

    case "$action" in
        start|stop|restart|status)
            if ! systemctl "$action" "$service_name"; then
                printer "$COLOR_RED" "ERROR" "Failed to $action $service_name"
                systemctl status "$service_name" --no-pager
                exit 1
            fi
            printer "$COLOR_GREEN" "OK" "$service_name $action completed"
            ;;
        *) die "Invalid action: $action" ;;
    esac
}

usage() {
    cat <<EOF
${SCRIPT_NAME} v${VERSION} - System administration toolkit

Usage:
  ${SCRIPT_NAME} check    Run system checks
  ${SCRIPT_NAME} service  Manage services
  ${SCRIPT_NAME} --debug  Enable debug mode

EOF
}

main() {
    load_config

    if [[ $# -eq 0 ]]; then usage; exit 0; fi
    [[ "$1" == "--debug" ]] && CONFIG[debug]=true && shift

    case "$1" in
        check) cmd_check "$@" ;;
        service) cmd_service "$@" ;;
        -h|--help) usage ;;
        --version) echo "$SCRIPT_NAME v$VERSION" ;;
        *) die "Unknown command: $1" ;;
    esac
}

main "$@"