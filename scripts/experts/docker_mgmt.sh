#!/usr/bin/env bash
#
#
#          FILE: docker-manager.sh
#
#         USAGE: ./docker-manager.sh [options] <command> [command-args...]
#
#   DESCRIPTION: Expert-level Docker management CLI.
#                Build, run, manage, and clean up Docker resources
#                with structured logging and safety features.
#
#       OPTIONS:
#         -c, --config <file>   Specify configuration file (default: docker-manager.conf)
#         -e, --env <file>      Specify environment file (default: .env if exists)
#         -y, --yes             Skip confirmation prompts
#         -v, --verbose         Enable verbose (debug) logging
#         -h, --help            Show help
#

set -o errexit
set -o nounset
set -o pipefail

# Default Config Values 
CONFIG_FILE="docker-manager.conf"
ENV_FILE=""
SKIP_CONFIRM=false
VERBOSE=false

APP_NAME="myapp"
IMAGE_NAME="my-docker-image"
IMAGE_TAG="latest"
DOCKERFILE="Dockerfile"
BUILD_CONTEXT="."
CONTAINER_NAME="my-app-container"
PORT_MAPPING="8080:80"
RESTART_POLICY="unless-stopped"

# Logging Functions  
log() {
    local level="$1"; shift
    local color_reset="\033[0m"
    local color_info="\033[1;34m"
    local color_warn="\033[1;33m"
    local color_error="\033[1;31m"

    case "$level" in
        INFO) echo -e "${color_info}[$level]$(date +'%F %T') - $*${color_reset}" ;;
        WARN) echo -e "${color_warn}[$level]$(date +'%F %T') - $*${color_reset}" ;;
        ERROR) echo -e "${color_error}[$level]$(date +'%F %T') - $*${color_reset}" ;;
        DEBUG) $VERBOSE && echo -e "[DEBUG] $(date +'%F %T') - $*" ;;
    esac
}

confirm() {
    if $SKIP_CONFIRM; then return 0; fi
    read -rp "Are you sure? (y/N) " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

# Helpers     
check_docker() {
    if ! command -v docker &>/dev/null; then
        log ERROR "Docker is not installed."
        exit 1
    fi
    if ! docker info &>/dev/null; then
        log ERROR "Docker daemon is not running."
        exit 1
    fi
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        log INFO "Loaded config from $CONFIG_FILE"
    else
        log WARN "Config file not found, using defaults."
    fi
}

detect_env_file() {
    if [[ -z "$ENV_FILE" && -f ".env" ]]; then
        ENV_FILE=".env"
        log INFO "Using detected environment file: $ENV_FILE"
    fi
}

# Docker Command Wrappers
build_image() {
    log INFO "Building image ${IMAGE_NAME}:${IMAGE_TAG}..."
    docker build \
        --tag "${IMAGE_NAME}:${IMAGE_TAG}" \
        --file "${BUILD_CONTEXT}/${DOCKERFILE}" \
        "${BUILD_CONTEXT}"
    log INFO "Build complete."
}

run_container() {
    log INFO "Running container: ${CONTAINER_NAME}..."
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log WARN "Container ${CONTAINER_NAME} already exists."
        return 1
    fi
    docker run -d \
        --name "${CONTAINER_NAME}" \
        --restart "${RESTART_POLICY}" \
        -p "${PORT_MAPPING}" \
        ${ENV_FILE:+--env-file "$ENV_FILE"} \
        "${IMAGE_NAME}:${IMAGE_TAG}"
    log INFO "Container started."
}

start_container() { log INFO "Starting container..."; docker start "${CONTAINER_NAME}"; }
stop_container() { log INFO "Stopping container..."; docker stop "${CONTAINER_NAME}"; }
restart_container() { log INFO "Restarting container..."; docker restart "${CONTAINER_NAME}"; }
show_logs() { docker logs -f "${CONTAINER_NAME}"; }
show_status() { docker ps -f "name=${CONTAINER_NAME}"; }
access_shell() { docker exec -it "${CONTAINER_NAME}" /bin/sh; }
exec_command() { docker exec -it "${CONTAINER_NAME}" "$@"; }

remove_image() {
    if confirm; then
        docker rmi "${IMAGE_NAME}:${IMAGE_TAG}"
        log INFO "Image removed."
    fi
}

remove_container() {
    if confirm; then
        docker rm -f "${CONTAINER_NAME}"
        log INFO "Container removed."
    fi
}

prune_docker() {
    if confirm; then
        docker system prune -af
        log INFO "Docker system pruned."
    fi
}

list_containers() { docker ps -a --filter "name=${CONTAINER_NAME}"; }
list_images() { docker images "${IMAGE_NAME}"; }

# CLI Parsing  
show_help() {
    grep '^# ' "$0" | sed 's/^# //'
}

parse_opts() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config) CONFIG_FILE="$2"; shift 2 ;;
            -e|--env) ENV_FILE="$2"; shift 2 ;;
            -y|--yes) SKIP_CONFIRM=true; shift ;;
            -v|--verbose) VERBOSE=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            build|run|start|stop|restart|logs|status|shell|exec|rmi|rm|prune|ps|images)
                COMMAND="$1"; shift; COMMAND_ARGS=("$@"); break ;;
            *) log ERROR "Unknown option or command: $1"; show_help; exit 1 ;;
        esac
    done
}

# Main            
main() {
    check_docker
    parse_opts "$@"
    load_config
    detect_env_file

    case "${COMMAND:-help}" in
        build) build_image ;;
        run) run_container ;;
        start) start_container ;;
        stop) stop_container ;;
        restart) restart_container ;;
        logs) show_logs ;;
        status) show_status ;;
        shell) access_shell ;;
        exec) exec_command "${COMMAND_ARGS[@]}" ;;
        rmi) remove_image ;;
        rm) remove_container ;;
        prune) prune_docker ;;
        ps) list_containers ;;
        images) list_images ;;
        help|*) show_help ;;
    esac
}

main "$@"