#!/bin/sh
# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Charles Phan - 4131861
# Created date: 30/08/2026
# Last modified: 11/09/2026
# Acknowledgement: None

# Render config.js from the environment, at container start.
#
# The API base URL is NOT baked into the JavaScript bundle. The browser reads
# it from config.js at page load, and Vite copies that file into dist/
# unhashed — so one built image can be pointed at any backend.
#
#   docker run -e API_BASE_URL=http://<api-ip>/api  ...   split hosts
#   docker run -e API_BASE_URL=/api                 ...   one nginx in front
#
set -eu

: "${API_BASE_URL:=/api}"

cat > /usr/share/nginx/html/config.js <<CONFIG
/* Generated at container start by 40-render-config-js.sh. Do not edit in
   place: the next container start overwrites it. Change API_BASE_URL and
   recreate the container instead. */
window.__APP_CONFIG__ = {
  API_BASE_URL: '${API_BASE_URL}'
}
CONFIG

echo "[entrypoint] config.js rendered with API_BASE_URL=${API_BASE_URL}"
