#!/bin/bash

set -o pipefail
set -e

# --- Helper Functions ---

usage() {
    cat <<EOF
Usage: $0 [-c|--config /path/to/config] [-d|--dry-run]

Options:
  -c, --config   Specify the configuration file to use (required).
  -d, --dry-run  Perform a trial run without making any changes.
  -h, --help     Show this help message and exit.
EOF
    exit 1
}

log() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - ${message}" | tee -a "${LOG_FILE}"
}

cleanup() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "Lock file removed."
    fi
}

# --- Argument Parsing ---

CONFIG_FILE=""
DRY_RUN_FLAG=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN_FLAG="--dry-run"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown parameter passed: $1"
            usage
            ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Configuration file not specified or not found."
    usage
fi

# --- Load Configuration ---

source "$CONFIG_FILE"

# Validate required config variables
if [[ -z "$SYNC_NAME" ]]; then
    echo "Error: SYNC_NAME must be set in the config file."
    exit 1
fi
if [[ -z "$SOURCE_DIR" ]]; then
    echo "Error: SOURCE_DIR must be set in the config file."
    exit 1
fi
if [[ -z "$DEST_DIR" ]]; then
    echo "Error: DEST_DIR must be set in the config file."
    exit 1
fi
if [[ -z "$SYNC_MODE" ]]; then
    echo "Error: SYNC_MODE must be set to 'one-way' or 'two-way' in the config file."
    exit 1
fi
if [[ -z "$LOG_FILE" ]]; then
    echo "Error: LOG_FILE must be set in the config file."
    exit 1
fi

# --- Setup ---

mkdir -p "$(dirname "$LOG_FILE")"

LOCK_FILE="/tmp/${SYNC_NAME}.lock"

if [[ -e "$LOCK_FILE" ]]; then
    echo "Another instance is already running (lock file exists at $LOCK_FILE). Exiting."
    exit 1
fi

trap cleanup EXIT SIGHUP SIGINT SIGTERM

touch "$LOCK_FILE"
log "Lock file created."

# Check rsync availability
if ! command -v rsync &> /dev/null; then
    log "Error: rsync is not installed. Please install it to continue."
    exit 1
fi

# Validate source and destination directories
if [[ ! -d "$SOURCE_DIR" ]]; then
    log "Error: Source directory $SOURCE_DIR does not exist."
    exit 1
fi

if [[ "$DEST_DIR" != *":"* ]] && [[ ! -d "$DEST_DIR" ]]; then
    log "Destination directory $DEST_DIR does not exist. Creating it."
    mkdir -p "$DEST_DIR"
fi

# --- Rsync Options ---

RSYNC_OPTS=(-avh --progress ${EXCLUDE_OPTS})

if [[ -n "$DRY_RUN_FLAG" ]]; then
    RSYNC_OPTS+=("--dry-run")
    log "Performing dry run - no changes will be made."
fi

# --- Sync Logic ---

if [[ "$SYNC_MODE" == "one-way" ]]; then
    log "Starting one-way sync from $SOURCE_DIR to $DEST_DIR"
    if [[ "$BACKUP_DELETED" == "true" ]]; then
        BACKUP_PATH="${BACKUP_DIR}/$(date +%F_%H-%M-%S)"
        mkdir -p "$BACKUP_PATH"
        RSYNC_OPTS+=(--delete --backup --backup-dir="$BACKUP_PATH")
        log "Backup for deleted/overwritten files enabled at $BACKUP_PATH"
    else
        RSYNC_OPTS+=(--delete)
    fi

    rsync "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$DEST_DIR/"
    RSYNC_EXIT_CODE=$?

elif [[ "$SYNC_MODE" == "two-way" ]]; then
    log "Starting two-way sync between $SOURCE_DIR and $DEST_DIR"

    log "Step 1: Syncing from $SOURCE_DIR to $DEST_DIR"
    rsync "${RSYNC_OPTS[@]}" --update "$SOURCE_DIR/" "$DEST_DIR/"
    RSYNC_EXIT_CODE_1=$?

    log "Step 2: Syncing from $DEST_DIR to $SOURCE_DIR"
    rsync "${RSYNC_OPTS[@]}" --update "$DEST_DIR/" "$SOURCE_DIR/"
    RSYNC_EXIT_CODE_2=$?

    if [[ $RSYNC_EXIT_CODE_1 -ne 0 ]] || [[ $RSYNC_EXIT_CODE_2 -ne 0 ]]; then
        RSYNC_EXIT_CODE=1
    else
        RSYNC_EXIT_CODE=0
    fi
else
    log "Error: Invalid SYNC_MODE specified. Must be 'one-way' or 'two-way'."
    exit 1
fi

# --- Post Sync ---

if [[ $RSYNC_EXIT_CODE -eq 0 ]]; then
    log "Sync completed successfully."
else
    log "Sync completed with errors (exit code: $RSYNC_EXIT_CODE)."
fi

log "--- Sync Job Finished ---"
exit $RSYNC_EXIT_CODE
