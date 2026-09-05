# Build the Vue application into static production assets. Node is confined to
# this stage and is not included in the final image.
FROM node:22-alpine AS build

WORKDIR /app

# Install dependencies before copying the source so Docker can reuse this layer
# when application code changes but the lockfile does not.
COPY app/client/package.json app/client/package-lock.json ./
RUN npm ci

COPY app/client/ ./
RUN npm run build

# Serve only the compiled SPA from a small nginx runtime image.
FROM nginx:stable-alpine AS runtime

# The nginx configuration handles static assets and Vue history-mode fallback.
# Runtime API configuration remains in /usr/share/nginx/html/config.js and can
# be replaced by the deployment without rebuilding the application bundle.
COPY docker/client-nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/ /usr/share/nginx/html/

# Document nginx's container port; the deployment chooses the published port.
EXPOSE 80
