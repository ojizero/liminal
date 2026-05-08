#!/bin/sh
set -e

PUID=${PUID:-911}
PGID=${PGID:-911}

addgroup --gid "$PGID" liminal 2>/dev/null || true
adduser --uid "$PUID" --ingroup liminal --home /app --shell /bin/sh --disabled-password --no-create-home --gecos "" liminal 2>/dev/null || true

chown "$PUID":"$PGID" /data
chown -R "$PUID":"$PGID" /app

exec gosu liminal "$@"
