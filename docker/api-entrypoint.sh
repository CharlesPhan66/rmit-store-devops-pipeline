#!/bin/sh
# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Charles Phan - 4131861
# Created date: 03/09/2026
# Last modified: 11/09/2026
# Acknowledgement: None

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
