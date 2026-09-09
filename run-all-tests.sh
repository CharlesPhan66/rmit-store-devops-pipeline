#!/usr/bin/env bash
set -e

export TARGET_URL="${TARGET_URL:-http://localhost}"

echo "=========================================================="
echo " Orchestrating Complete Testing Suite "
echo " Target: ${TARGET_URL}"
echo "=========================================================="

# Ensure output report directories exist
mkdir -p reports/coverage-html reports/e2e-html-report

# =========================================================================
# 0. ENSURE NODE & PLAYWRIGHT DEPENDENCIES
# =========================================================================
echo ">>> [0/4] Checking Node & Browser Dependencies..."

# Allocate swap memory if system has 0 swap (prevents browser launch deadlock)
if [ "$(free -m | awk '/Swap:/ {print $2}')" -eq 0 ]; then
  echo ">>> [0/5] No swap detected. Allocating 2GB swapfile..."
  if [ ! -f /swapfile ]; then
    sudo dd if=/dev/zero of=/swapfile bs=128M count=16
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
  fi
  sudo swapon /swapfile 2>/dev/null || true
  grep -q "/swapfile" /etc/fstab || echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
fi

# Install node dependencies and browser binaries if absent
if [ ! -d "node_modules" ]; then
  echo "Installing Node dev dependencies..."
  npm install -D @playwright/test vitest vite @vitejs/plugin-vue jsdom @vitest/coverage-v8 pinia axios
fi

# Ensure Chromium browser binary is present in ~/.cache/ms-playwright
npx playwright install chromium

# =========================================================================
# 1. RUN BACKEND UNIT & INTEGRATION TESTS
# =========================================================================
echo ">>> [1/4] Running Backend Pytest Suite..."

if [ ! -d ".venv" ]; then
  python3.11 -m venv .venv
fi

source .venv/bin/activate
python3 -m pip install --quiet --upgrade pip

# Pin Django to 4.2 LTS to maintain compatibility with Python 3.9
pip install --quiet "Django>=4.2,<5.0"

# Install project app requirements if present
if [ -f "app/server/requirements.txt" ]; then
  pip install --quiet -r app/server/requirements.txt
elif [ -f "requirements.txt" ]; then
  pip install --quiet -r requirements.txt
fi

# Explicit installs compatible with Python 3.9 / Django 4.2
pip install --quiet django-environ djangorestframework djangorestframework-simplejwt

# Install dev/test requirements
if [ -f "tests/backend/requirements-dev.txt" ]; then
  pip install --quiet -r tests/backend/requirements-dev.txt
fi

export PYTHONPATH=".:app/server:$PYTHONPATH"
pytest tests/backend/ -c tests/backend/pytest.ini --junitxml=reports/junit-backend.xml

# =========================================================================
# 2. RUN FRONTEND UNIT TESTS
# =========================================================================
echo ">>> [2/4] Running Frontend Unit Tests..."

npx vitest run --config tests/frontend/vite.config.mjs

# =========================================================================
# 3. RUN PLAYWRIGHT END-TO-END ACCEPTANCE JOURNEYS
# =========================================================================
echo ">>> [3/4] Running Playwright E2E Tests..."

npx playwright test --config=tests/e2e/playwright.config.mjs

# =========================================================================
# 4. RUN DEPLOYMENT SMOKE PROBE VALIDATION
# =========================================================================
echo ">>> [4/4] Running Deployment Smoke Probes..."

pytest tests/smoke/test_smoke.py -m smoke --junitxml=reports/junit-smoke.xml

echo "=========================================================="
echo " Testing Suite Execution Complete. All Reports Published."
echo "=========================================================="