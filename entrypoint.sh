#!/bin/sh
set -e

PUID=${PUID:-911}
PGID=${PGID:-911}

groupmod -o -g "$PGID" liminal
usermod -o -u "$PUID" liminal

chown -R "$PUID":"$PGID" /app

exec gosu liminal "$@"
