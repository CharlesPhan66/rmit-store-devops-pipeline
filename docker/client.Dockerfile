# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Authors: Dang Khoa - 4058813, Nguyen Cong Quoc Dat - 4066942, Charles Phan - 4131861
# Created date: 31/08/2026
# Last modified: 11/09/2026
# Acknowledgement: None

# RMIT Store — frontend image (Vue 3 SPA served by nginx).

# Stage 1 — compile the bundle
FROM node:22-alpine AS build

WORKDIR /build

COPY app/client/package.json app/client/package-lock.json ./
RUN npm ci

COPY app/client/ ./

RUN npm run build

# Stage 1b — frontend unit tests (Vitest + jsdom). Not shipped in the runtime image.
FROM node:22-alpine AS test

WORKDIR /repo

COPY app/client/package.json app/client/package-lock.json app/client/
RUN cd app/client && npm ci

RUN npm init -y >/dev/null && npm install --no-save \
    vitest@^2.1 @vitest/coverage-v8@^2.1 jsdom@^25 \
    vue@^3.5 pinia@^2.2 @vitejs/plugin-vue@^5.2

COPY app/client/ app/client/
COPY tests/ tests/

CMD ["npx", "vitest", "run", "--config", "tests/frontend/vite.config.mjs"]

# Stage 2 — serve
FROM nginx:1.27-alpine AS runtime

COPY docker/client-nginx.conf /etc/nginx/conf.d/default.conf

COPY docker/client-entrypoint.sh /docker-entrypoint.d/40-render-config-js.sh
RUN chmod +x /docker-entrypoint.d/40-render-config-js.sh

COPY --from=build /build/dist/ /usr/share/nginx/html/

EXPOSE 80
