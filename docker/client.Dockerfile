# RMIT Store — frontend image (Vue 3 SPA served by nginx).
#
# Please build from the repo root, not app/client/:
#
#     docker build -f docker/client.Dockerfile -t rmit-client:local .
#
# Multi-stage on purpose. Node compiles the bundle; the result is a folder of
# static files. THE FINAL IMAGE MUST NOT CONTAIN NODE.
# To verify, run the image and check that `which node` prints nothing:
#
#     docker run --rm rmit-client:local which node    # should print nothing

# Stage 1 — compile the bundle
FROM node:22-alpine AS build

WORKDIR /build

# Lockfile first, so `npm ci` is cached until a dependency actually changes.
# ci instead of install because it needs to stick to the lockfile, auto-updating to new versions is not desired.
COPY app/client/package.json app/client/package-lock.json ./
RUN npm ci

# Copy the rest of the source code and build the bundle in this stage and copy the result to the final image.
# This stage is discarded after build, so it does not count toward the final image size.
# This stage has node and all the build tools, but the final image does not.
# That's why `docker run --rm rmit-client:local which node` should print nothing.
COPY app/client/ ./

RUN npm run build

# Stage 1b — frontend unit tests (Vitest + jsdom). Not shipped in the runtime image.
#
#   docker build -f docker/client.Dockerfile --target test -t rmit-client:test .
#   docker run --rm -v "$PWD/reports:/repo/reports" rmit-client:test
#
# Layout matches what tests/frontend/vite.config.mjs expects: the client under
# /repo/app/client and the libs its aliases resolve at /repo/node_modules. The
# app's own package.json is not modified.
FROM node:22-alpine AS test

WORKDIR /repo

COPY app/client/package.json app/client/package-lock.json app/client/
RUN cd app/client && npm ci

# Test tooling plus the libs tests/frontend/vite.config.mjs resolves from
# /repo/node_modules. Throwaway package.json, never written back to the repo.
RUN npm init -y >/dev/null && npm install --no-save \
    vitest@^2.1 @vitest/coverage-v8@^2.1 jsdom@^25 \
    vue@^3.5 pinia@^2.2 @vitejs/plugin-vue@^5.2

COPY app/client/ app/client/
COPY tests/ tests/

CMD ["npx", "vitest", "run", "--config", "tests/frontend/vite.config.mjs"]

# Stage 2 — serve
FROM nginx:1.27-alpine AS runtime

COPY docker/client-nginx.conf /etc/nginx/conf.d/default.conf

# Copy the script to the entrypoint folder and make it executable.
# The script is run at container start, not at build, so it can read environment variables set at runtime.
# This allow you to set the API base URL at runtime (pass it as an environment variable), not at build time, which is important for flexibility and deployment.
COPY docker/client-entrypoint.sh /docker-entrypoint.d/40-render-config-js.sh
RUN chmod +x /docker-entrypoint.d/40-render-config-js.sh

COPY --from=build /build/dist/ /usr/share/nginx/html/

EXPOSE 80
