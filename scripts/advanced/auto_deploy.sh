#!/usr/bin/env bash
#This script automates secure file deployments from your local machine to a remote server using rsync over SSH. It copies files from a specified local directory (like ./build) to a target server (user@example.com:/var/www/myapp), with optional features like backups, post-deployment commands (e.g., restarting services), dry-run testing, and rollback to previous versions if something goes wrong.
set -eo pipefail
IFS=$'\n\t'

# Configuration defaults
DRY_RUN=false
VERBOSE=false
MAX_BACKUPS=5
RSYNC_ARGS=(-az --delete)
SSH_ARGS=(-o "ConnectTimeout=10" -o "StrictHostKeyChecking=yes")

log_file=""

usage() {
  cat <<EOF
Usage: $0 [OPTIONS] -s SOURCE_PATH -t USER@HOST -d REMOTE_DIR

Deploy files via rsync over SSH with optional backup, rollback, and post-deploy command.

Required:
  -s SOURCE_PATH    Local file/directory to deploy
  -t TARGET         Remote target (user@host)
  -d DEST_DIR       Remote destination directory

Options:
  -c COMMAND        Remote command to execute after sync (e.g. "systemctl restart app")
  -b BACKUP_PREFIX  Create timestamped backup with this prefix (keeps last $MAX_BACKUPS)
  -n                Dry-run mode (show what would be done)
  -v                Verbose output
  -e SSH_EXTRA_ARGS Extra SSH arguments (e.g. "-i /path/to/key")
  -r RSYNC_EXTRA    Extra rsync arguments (e.g. "--exclude=tmp")
  -k                Keep all backups (don't rotate)
  -R                Rollback to most recent backup
  -f FILE           Save all log output to this file
  -h                Show this help

Examples:
  $0 -s ./build -t deploy@host -d /var/www/myapp
  $0 -s ./dist -t user@prod -d /opt/app -c "sudo systemctl restart app" -b v1 -f deploy.log
EOF
  exit 0
}

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  [[ -n "$log_file" ]] && echo "$msg" >> "$log_file"
}

error() {
  log "ERROR: $1" >&2
  exit 1
}

validate_ssh() {
  if ! ssh "${SSH_ARGS[@]}" "$target" true; then
    error "SSH connection failed to $target"
  fi
}

validate_paths() {
  [[ -e "$src" ]] || error "Source not found: $src"
  if ! ssh "${SSH_ARGS[@]}" "$target" "test -d $(dirname "$dest")"; then
    error "Parent directory doesn't exist on remote: $(dirname "$dest")"
  fi
}

create_backup() {
  local backup_dir="${dest}_${backup}_${timestamp}"
  log "Creating backup: $backup_dir"
  ssh "${SSH_ARGS[@]}" "$target" "cp -a \"$dest\" \"$backup_dir\"" || error "Backup failed"

  if [[ $keep_backups != true ]]; then
    log "Rotating backups (keeping last $MAX_BACKUPS)"
    ssh "${SSH_ARGS[@]}" "$target" \
      "ls -dt \"${dest}_${backup}_\"* 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs rm -rf --"
  fi
}

rollback() {
  local latest_backup
  latest_backup=$(ssh "${SSH_ARGS[@]}" "$target" \
    "ls -dt \"${dest}_${backup}_\"* 2>/dev/null | head -n 1")

  [[ -n "$latest_backup" ]] || error "No backups found for rollback"

  log "Rolling back to: $latest_backup"
  ssh "${SSH_ARGS[@]}" "$target" \
    "rm -rf \"$dest\" && cp -a \"$latest_backup\" \"$dest\"" || error "Rollback failed"

  log "Rollback complete. Current deployment is now from $latest_backup"
  exit 0
}

main() {
  local src="" target="" dest="" cmd="" backup=""
  local keep_backups=false rollback_mode=false
  local ssh_extra=() rsync_extra=()

  while getopts ":s:t:d:c:b:e:r:nvkhRf:" opt; do
    case $opt in
      s) src=$OPTARG ;;
      t) target=$OPTARG ;;
      d) dest=$OPTARG ;;
      c) cmd=$OPTARG ;;
      b) backup=$OPTARG ;;
      e) IFS=' ' read -ra ssh_extra <<< "$OPTARG" ;;
      r) rsync_extra+=("$OPTARG") ;;
      n) DRY_RUN=true ;;
      v) VERBOSE=true ;;
      k) keep_backups=true ;;
      R) rollback_mode=true ;;
      f) log_file=$OPTARG ;;
      h) usage ;;
      *) error "Invalid option: -$OPTARG" ;;
    esac
  done
  shift $((OPTIND-1))

  [[ -z "$src" || -z "$target" || -z "$dest" ]] && usage

  # Configure SSH and rsync arguments
  SSH_ARGS+=("${ssh_extra[@]}")
  [[ $VERBOSE == true ]] && RSYNC_ARGS+=(-v) || RSYNC_ARGS+=(-q)
  RSYNC_ARGS+=("${rsync_extra[@]}")

  # Validate inputs
  validate_ssh
  validate_paths

  # Handle rollback
  if [[ $rollback_mode == true ]]; then
    [[ -n "$backup" ]] || error "Backup prefix required for rollback (-b)"
    rollback
  fi

  timestamp=$(date -u +"%Y%m%dT%H%M%SZ")

  # Optional backup
  if [[ -n "$backup" ]]; then
    create_backup
  fi

  # Perform deployment
  log "Starting deployment from $src to ${target}:${dest}"

  if [[ $DRY_RUN == true ]]; then
    log "DRY RUN - would execute:"
    log "rsync ${RSYNC_ARGS[*]} --dry-run \"$src\" \"${target}:${dest}\""
    rsync "${RSYNC_ARGS[@]}" --dry-run "$src" "${target}:${dest}" | tee >( [[ -n "$log_file" ]] && tee -a "$log_file" > /dev/null )
  else
    rsync "${RSYNC_ARGS[@]}" "$src" "${target}:${dest}" | tee >( [[ -n "$log_file" ]] && tee -a "$log_file" > /dev/null ) || error "rsync failed"
  fi

  # Remote post-deploy command
  if [[ -n "$cmd" ]]; then
    log "Executing remote command: $cmd"
    [[ $DRY_RUN == false ]] && ssh "${SSH_ARGS[@]}" "$target" "$cmd"
  fi

  log "Deployment completed successfully"
}

main "$@"
