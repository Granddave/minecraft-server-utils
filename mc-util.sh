#!/usr/bin/env bash

set -x

function log()
{
	echo "[$(date --iso-8601=ns)] $*" | tee -a /tmp/mc-util.log
}

function send_command()
{
	COMMAND="$1"
	log "Running command: $COMMAND"
	docker exec $CONTAINER_NAME rcon-cli "$COMMAND"
}

function total_backup_size()
{
	echo $(du -s $BACKUP_DIR | cut -f1)
}

function backup_count()
{
	echo $(find $BACKUP_DIR -type f | wc -l)
}

function archive_backup()
{
	log "Archiving..."
	BACKUP_DIR="$SERVER_DIR/backups"
	mkdir -p $BACKUP_DIR
	ROTATE_THRESHOLD=6000000
	log "Num backups: $(backup_count) ($(total_backup_size)B)"
	while [ $(backup_count) -gt 1 ] && [ $(total_backup_size) -gt $ROTATE_THRESHOLD ]; do
		OLDEST_BACKUP=$(find $BACKUP_DIR -type f -printf '%T+ %p\n' | sort | head -n 1 | cut -d" " -f2)
		if [ -f "$OLDEST_BACKUP" ]; then
			log "Removing $OLDEST_BACKUP"
			rm -v "$OLDEST_BACKUP"
		fi
		log "Num backups: $(backup_count) ($(total_backup_size)B)"
	done
	TMP_DIR=$(mktemp -d)
	cp -r "$SERVER_DIR/world" "$TMP_DIR"
	pushd "$TMP_DIR"
	TIMESTAMP=$(date "+%F_%T" | tr ":" "_")
	BACKUP_FILENAME="backup_$TIMESTAMP.tar.gz"
	tar czvf "$BACKUP_DIR/$BACKUP_FILENAME" "$TMP_DIR"
	popd
	rm -rf $TMP_DIR
	log "Done"
}

function do_backup()
{
	# TODO: Only backup if any players are online
	send_command "say Starting backup in 5 sec..."
	sleep 5
	send_command "say Starting backup"
	send_command "save-off"
	send_command "save-all"
	sleep 1
	archive_backup
	send_command "save-on"
	send_command "say Backup complete"
}

function run_command_file()
{
	FILEPATH="$1"
	[ -f $FILEPATH ] || (log "$FILEPATH doesn't exist"; exit 1)
	while read CMD; do
		if [ -n "$CMD" ]; then
			send_command "$CMD"
		fi
	done < $FILEPATH
}

function is_server_running()
{
	send_command "list" 2>&1 > /dev/null
	return $?
}

CONTAINER_NAME="${CONTAINER_NAME:-minecraft_vanilla_minecraft_1}"
SERVER_DIR="${SERVER_DIR:-/data/compose/minecraft_vanilla/data}"

if [ ! -d "$SERVER_DIR/world" ]; then
	log "Did not find 'world' dir in $SERVER_DIR"
	exit 1
fi

if ! is_server_running; then
	log "No connection to server: $CONTAINER_NAME"
	exit 1
fi

log "$0 started with \"$*\""
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
