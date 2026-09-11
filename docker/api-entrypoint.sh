#!/bin/sh
# Swarm delivers secrets as files; Django reads environment variables.
# Every file in /run/secrets/ becomes an env var of the same name.
set -e

if [ -d /run/secrets ]; then
  for f in /run/secrets/*; do
    [ -f "$f" ] || continue
    export "$(basename "$f")"="$(cat "$f")"
  done
fi

exec "$@"
