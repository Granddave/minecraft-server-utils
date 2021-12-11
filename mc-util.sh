#!/usr/bin/env bash
# vi: tabstop=4 shiftwidth=4 expandtab

log()
{
    echo "[$(date --iso-8601=ns)] $*" | tee -a "/tmp/mc-util_$CONTAINER_NAME.log"
}

send_command()
{
    local command="$1"
    log "Running command: $command"
    docker exec "$CONTAINER_NAME" rcon-cli "$command"
}

total_backup_size()
{
    du -sb "$BACKUP_DIR" | cut -f1
}

backup_count()
{
    find "$BACKUP_DIR" -maxdepth 1 -type f | wc -l
}

latest_backup_size()
{
    if [ "$(find "$BACKUP_DIR" -type f | wc -l)" -ne 0 ]; then
        local latest_backup
        latest_backup=$(find "$BACKUP_DIR" -type f -printf '%T+ %p\n' | sort | tail -n 1 | cut -d" " -f2)
        du -sh "$latest_backup" | cut -f1
    fi
}

log_backup_status()
{
    log "Num backups: $(backup_count) ($(total_backup_size | numfmt --to=iec))"
}

create_backup()
{
    log "Creating backup..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    cp -r "$SERVER_DIR/world" "$tmp_dir"
    if ! pushd "$tmp_dir"; then
        log "Failed to create temporary directory '$tmp_dir'"
        exit 1
    fi
    local timestamp
    timestamp=$(date "+%F_%T" | tr ":" "_")
    local backup_filename="backup_$timestamp.tar.gz"
    if [ "$(mkdir -p "$BACKUP_DIR")" ]; then
        log "Failed to create $BACKUP_DIR"
        exit 1
    fi
    tar czvf "$BACKUP_DIR/$backup_filename" world
    if ! popd; then
        log "Failed to cd back"
        exit 1
    fi
    rm -rf "$tmp_dir"
}

rotate_backups()
{
    log "Rotating backups..."
    log_backup_status
    while [ "$(backup_count)" -gt 1 ] && [ "$(total_backup_size)" -gt "$(numfmt --from=iec "$BACKUP_DIR_SIZE_MAX")" ]; do
        local oldest_backup
        oldest_backup=$(find "$BACKUP_DIR" -type f -printf '%T+ %p\n' | sort | head -n 1 | cut -d" " -f2)
        if [ -f "$oldest_backup" ]; then
            log "Removing $oldest_backup"
            rm -v "$oldest_backup"
        fi
        log_backup_status
    done
    return
}

has_players_online()
{
    if [ "$(send_command "list" | grep "There are" | cut -d" " -f3)" -gt 0 ]; then
        return 0
    fi
    return 1
}

do_backup()
{
    if ! has_players_online && [ -z "$FORCE_BACKUP" ]; then
        log "No player online, aborting."
        exit 0
    fi

    send_command "say Starting backup in 5 sec..."
    sleep 5
    send_command "say Starting backup"
    send_command "save-off"
    send_command "save-all"
    sleep 1
    SECONDS=0
    create_backup
    rotate_backups
    send_command "save-on"
    send_command "say Backup complete, took $SECONDS seconds ($(latest_backup_size)). Total $(backup_count) backups ($(total_backup_size | numfmt --to=iec))"
    log "Done"
}

run_command_file()
{
    local filepath="$1"
    if [ ! -f "$filepath" ]; then
        log "$filepath doesn't exist"
        exit 1
    fi
    while read -r cmd; do
        if [ -n "$cmd" ]; then
            send_command "$cmd"
        fi
    done < "$filepath"
}

is_server_running()
{
    send_command "list" > /dev/null 2>&1
    return $?
}

require_variable()
{
    local variable_name="$1"
    if [ -z "${!variable_name}" ]; then
        log "Environment variable $variable_name not set"
        exit 1
    fi
}

# Required envs
require_variable "CONTAINER_NAME"
require_variable "SERVER_DIR"

# Optional envs
BACKUP_DIR_SIZE_MAX=${BACKUP_DIR_SIZE_MAX:-"6G"}
FORCE_BACKUP=${FORCE_BACKUP:-}

# Constants
BACKUP_DIR=${BACKUP_DIR:-"/data/backups/$CONTAINER_NAME/worlds"}

if [ ! -f "$SERVER_DIR/world/level.dat" ]; then
    log "Did not find a world in $SERVER_DIR. Is this really a Minecraft server directory?"
    exit 1
fi

if ! is_server_running; then
    log "Failed to send RCON command to $CONTAINER_NAME. Is the server really running?"
    exit 1
fi

case $1 in
    "backup")
        do_backup
        ;;
    "cmd")
        shift
        send_command "$1"
        ;;
    "cmd-file")
        shift
        run_command_file "$1"
        ;;
    *)
        echo "Usage: $0 backup|cmd COMMAND|cmd-file COMMAND_FILE"
        ;;
esac
