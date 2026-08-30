# RMIT Store — API image (Django + gunicorn).
#
# Please build from the repo root, not app/server/. Tom's application is
# placed under one level down, so every COPY source carries the app/ prefix:
#
# How to build this image from the repo root:
#     docker build -f docker/api.Dockerfile -t rmit-api:local .

# Stage 1 — build the virtualenv (This stage doesn't count toward to the final image)
FROM python:3.12-slim AS builder

# Optimize pip: disable version check and local cache for faster, smaller builds
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

# requirements.txt alone first
COPY app/server/requirements.txt .

RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install -r requirements.txt

# Stage 2 - Runtime: This final stage forms the actual Docker image, discarding all temporary build files to minimize size
FROM python:3.12-slim AS runtime

# How to build this image from the repo root with custom version and commit:
#     docker build -f docker/api.Dockerfile \
#       --build-arg APP_VERSION=1.0.0 \
#       --build-arg GIT_COMMIT="$(git rev-parse --short HEAD)" \
#       -t rmit-api:local .
#
# Otherwise, defaults are used for local builds (APP_VERSION=1.0.0, GIT_COMMIT=dev).
ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=dev

# Set environment variables for Python and Django, including the application version and Git commit hash.
# These variables are used to configure the runtime environment and ensure that the application runs with the correct settings.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    DJANGO_SETTINGS_MODULE=config.settings.prod \
    APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT}

# Secure the container by running as a non-privileged user with no shell access
RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin app

# Set absolute path as the current directory for all subsequent commands
WORKDIR /srv/app

COPY --from=builder /opt/venv /opt/venv
COPY app/server/ /srv/app/

# collectstatic runs at BUILD time, deliberately.
#
# The three dummy values below exist only because config.settings.prod fails
# fast on an unset SECRET_KEY / ALLOWED_HOSTS. They are shell variables scoped
# to this one RUN, never ENV, so they are not present in the running container
# and do not appear in `docker inspect`. collectstatic touches no database.

# Bypass Django checks with dummy vars to run collectstatic, then create media directory and transfer ownership to the app user
RUN SECRET_KEY=build-time-only-never-used-at-runtime \
    ALLOWED_HOSTS=build.invalid \
    DATABASE_URL=postgres://build:build@127.0.0.1:5432/build \
    python manage.py collectstatic --noinput \
 && mkdir -p /srv/app/media \
 && chown -R app:app /srv/app/media /srv/app/staticfiles

USER app

EXPOSE 8000

# Ping /healthz/ every 30s to check app responsiveness; marks container unhealthy after 3 consecutive failures
HEALTHCHECK --interval=30s --timeout=3s --start-period=15s --retries=3 \
  CMD python -c "import sys,urllib.request; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz/', timeout=2).status == 200 else 1)"

# NOTE: no migrate here, and none in an entrypoint either. Migrations change
# shared state that lives outside the container; N replicas each running them
# at boot is a race. They are a one-shot job per release — see plan-d.
CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8000", \
     "--workers", "3", \
     "--timeout", "60", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
