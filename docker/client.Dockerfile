# syntax=docker/dockerfile:1
#
# RMIT Store — frontend image (Vue 3 SPA served by nginx).
#
# BUILD CONTEXT IS THE REPO ROOT:
#
#     docker build -f docker/client.Dockerfile -t rmit-client:local .
#
# Multi-stage on purpose. Node compiles the bundle; the result is a folder of
# static files. THE FINAL IMAGE MUST NOT CONTAIN NODE — verify, do not assume:
#
#     docker run --rm rmit-client:local which node    # prints nothing

# Stage 1 — compile the bundle
FROM node:22-alpine AS build

WORKDIR /build

# Lockfile first, so `npm ci` is cached until a dependency actually changes.
COPY app/client/package.json app/client/package-lock.json ./
RUN npm ci

COPY app/client/ ./

RUN npm run build

# Stage 2 — serve
FROM nginx:1.27-alpine AS runtime

COPY docker/client-nginx.conf /etc/nginx/conf.d/default.conf

# The nginx image runs every executable in /docker-entrypoint.d/ before
# starting nginx. This is where config.js is rendered from $API_BASE_URL —
# at container start, not at build. See the script for why that matters.
COPY docker/client-entrypoint.sh /docker-entrypoint.d/40-render-config-js.sh
RUN chmod +x /docker-entrypoint.d/40-render-config-js.sh

COPY --from=build /build/dist/ /usr/share/nginx/html/

EXPOSE 80
