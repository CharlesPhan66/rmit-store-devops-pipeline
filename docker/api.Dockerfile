# syntax=docker/dockerfile:1
#
# RMIT Store — API image (Django + gunicorn).
#
# BUILD CONTEXT IS THE REPO ROOT, not app/server/. Tom's application is
# vendored one level down, so every COPY source carries the app/ prefix:
#
#     docker build -f docker/api.Dockerfile -t rmit-api:local .
#
# A COPY source missing that prefix is the single most likely cause of a
# "file not found" on a first build.

# ---------------------------------------------------------------------------
# Stage 1 — build the virtualenv
# ---------------------------------------------------------------------------
# Separated from the runtime stage so that pip's caches, and any compiler
# needed by a package without a wheel, never reach the shipped image.
FROM python:3.12-slim AS builder

# # Optimize pip: disable version check and local cache for faster, smaller builds
ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

# requirements.txt alone first: this layer is cached until the dependency list
# itself changes, so an edit to a view does not reinstall Django.
COPY app/server/requirements.txt .

RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install --upgrade pip \
 && /opt/venv/bin/pip install -r requirements.txt

# Stage 2 - Runtime: This final stage forms the actual Docker image, discarding all temporary build files to minimize size
FROM python:3.12-slim AS runtime

# Overridable via --build-arg at build time; otherwise defaults apply
ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=dev

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
