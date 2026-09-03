# Using official python runtime base image
FROM python:3.11-slim

# Check whether Django can serve requests
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz/', timeout=3)"

# Python container settings
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Set the application directory
WORKDIR /app

# Install dependencies from requirement.txt
COPY requirements.txt .

RUN pip install --upgrade pip \
    && pip install -r requirements.txt

# Create a non-root application user
RUN addgroup --system app \
    && adduser --system --ingroup app app \
    && chown app:app /app

# Copy the Django source code
COPY --chown=app:app . .

# Run the application as the non-root user
USER app

# Make port 8000 available for links and/or publish
EXPOSE 8000

# Define our command to be run when launching the container
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000"]
