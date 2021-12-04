# Minecraft Server Utils

Utility script for backing up the server and running RCON commands.

## Assumed setup

This utility script...

- is written for and tested with the [itzg/minecraft-server](https://hub.docker.com/r/itzg/minecraft-server)
  docker image (vanilla server). It may work for other setups as well.
- assumes that the data directory is bind mounted (i.e. not in a volume).

## Functionality

- World backup
- RCON
  - Ad hoc command
  - Command file

## Usage

To run the script some environment variables needs to be set:

- **Required environment variables**
  - `CONTAINER_NAME` - Docker container name, e.g. `minecraft_vanilla_1`
  - `SERVER_DIR` - Path to server directory mount, e.g. `/data/minecraft_vanilla_1/data`

Output will be sent to STDOUT as well as `/tmp/mc-util_$CONTAINER_NAME.log`

### Backup

`./mc-util.sh backup`

Creates a backup of the world, compresses it to `$SERVER_DIR/backups` and rotates the backups if
the total size exceeds the `$BACKUP_DIR_SIZE_MAX`.

- **Optional environment variables**
  - `BACKUP_DIR_SIZE_MAX` - Maximum size of backups to keep in `$SERVER_DIR/backups`, e.g. `5G` or
    `500M`. Default `6G`.
  - `FORCE_BACKUP` - If set, run backup even if no players are online, e.g. `1`. Default *unset*.

Example cronjob that takes a two times an hour:

```
*/30 * * * * CONTAINER_NAME=minecraft_vanilla_1 SERVER_DIR=/data/minecraft_vanilla_1/data /data/scripts/mc-util.sh backup
```

### RCON Command execution

There are two ways of running commands;

- Ad hoc command: `./mc-util.sh cmd COMMAND`
- Command file: `./mc-util.sh cmd-file COMMAND_FILE`

where the `COMMAND_FILE` is a file with commands separated with newlines. E.g.

```
spawnRadius 0
playersSleepingPercentage 25
```

See all wiki for [available commands](https://minecraft.fandom.com/wiki/Commands) and
[gamerules](https://minecraft.fandom.com/wiki/Game_rule).
