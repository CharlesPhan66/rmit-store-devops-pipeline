# Using official python runtime base image
FROM python:3.11-slim AS runtime

ARG APP_VERSION=1.0.0
ARG GIT_COMMIT=dev

# Python container settings
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    APP_VERSION=${APP_VERSION} \
    GIT_COMMIT=${GIT_COMMIT}

# Set the application directory
WORKDIR /app

# Install dependencies from requirement.txt
COPY app/server/requirements.txt ./requirement.txt

RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Create a non-root application user
RUN addgroup --system app \
    && adduser --system --ingroup app app \
    && mkdir -p /app/media /app/staticfiles \
    && chown app:app /app

# Copy the Django source code
COPY --chown=app:app app/server/ ./

# Run the application as the non-root user
USER app

# Production uses WhiteNoise's manifest storage. These values exist only for
# this build command and are not persisted as runtime secrets.
RUN DJANGO_SETTINGS_MODULE=config.settings.prod \
    SECRET_KEY=container-build-only-not-a-runtime-secret \
    ALLOWED_HOSTS=localhost \
    python manage.py collectstatic --noinput

# Image-level liveness is intentionally dependency-free. Compose overrides this
# with /readyz/ when it needs database and storage readiness.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz/', timeout=3)"

# Make port 8000 available for links and/or publish
EXPOSE 8000

# Define our command to be run when launching the container
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--access-logfile", "-", "--error-logfile", "-"]
