# RMIT Store – Automated Testing Suite Documentation

This repository contains the end-to-end verification, integration, unit, and deployment smoke testing suite for the RMIT Store application. The suite validates all core functional capabilities across backend Django services, frontend components, and full user acceptance journeys.

---

## Test Suite Architecture

The testing pipeline is split into four distinct, sequential testing tiers orchestrated via `run-all-tests.sh`:

| Tier                    | Focus                                                        | Framework / Runner            | Target Directory  |
| :---------------------- | :----------------------------------------------------------- | :---------------------------- | :---------------- |
| **1. Backend**          | REST APIs, RBAC, Checkout, Payments, Database Models         | Pytest, Django Test, Coverage | `tests/backend/`  |
| **2. Frontend**         | Cart state, pricing calculators, currency formatters         | Vitest, JSDOM, Pinia          | `tests/frontend/` |
| **3. Acceptance (E2E)** | Full multi-page browser journeys (Customer, Merchant, Admin) | Playwright, Chromium          | `tests/e2e/`      |
| **4. Smoke Probes**     | Deployment health, live API probes, latency gates            | Pytest, Requests              | `tests/smoke/`    |

---

## Directory Structure

```text
.
├── pytest.ini                            # Global Pytest configuration
├── run-all-tests.sh                      # Master test execution script
├── tests/
│   ├── backend/                          # Backend test suite
│   │   ├── pytest.ini                    # Backend-specific pytest settings
│   │   ├── requirements-dev.txt          # Python dev & test dependencies
│   │   ├── test_api.py                   # Catalog and general API test cases
│   │   ├── test_checkout.py              # Order placement and checkout pipeline
│   │   ├── test_payments.py              # Card authorization & decline flows
│   │   ├── test_rbac.py                  # Role-Based Access Control verification
│   │   └── test_settings.py              # Django test settings override
│   ├── frontend/                         # Client-side component & unit tests
│   │   ├── cart.spec.js                  # Pinia cart calculation & badge tests
│   │   ├── formatters.spec.js            # Currency & date formatters
│   │   └── vite.config.mjs               # Vitest runner configuration
│   ├── e2e/                              # End-to-end acceptance journeys
│   │   ├── journeys.spec.js              # Playwright test specs (Journeys 1 to 7)
│   │   └── playwright.config.mjs         # Headless browser & artifact configuration
│   └── smoke/                            # Deployment health probes
│       └── test_smoke.py                 # Live URL status & readiness checks
```

---

## Prerequisites & System Dependencies

When running tests on Red Hat-based Linux distributions (Amazon Linux 2023), execute the following system preparation commands to install Node.js 20.x, Python 3.10+, and the system-level libraries required by Playwright’s headless Chromium engine.

#### 1. Install Node.js

```bash
curl -fsSL [https://rpm.nodesource.com/setup_20.x](https://rpm.nodesource.com/setup_20.x) | sudo bash -
sudo dnf install -y nodejs
```

#### 2. Install Headless Chromium System Dependencies

```bash
sudo dnf install -y \
  alsa-lib atk at-spi2-atk at-spi2-core cairo cups-libs dbus-libs \
  expat fontconfig freetype glib2 gtk3 libX11 libXcomposite \
  libXdamage libXext libXfixes libXi libXrandr libXrender libXtst \
  libdrm libxcb libxkbcommon libxshmfence mesa-libgbm nspr nss \
  nss-util pango
```

---

## Executing the Test Suite

#### Running the Entire Suite via Orchestrator

The test runner script `run-all-tests.sh` executes all 4 testing tiers sequentially, reports progress to the console, and writes JUnit XML and HTML artifacts to `reports/`.

```bash
# Clean existing virtual environment if dirty
rm -rf .venv

# Ensure execution permissions
chmod +x run-all-tests.sh

# Option A: Run against local container stack
TARGET_URL="[http://127.0.0.1](http://127.0.0.1)" ./run-all-tests.sh

# Option B: Run against public EC2 instance IP
TARGET_URL="http://<YOUR-EC2-PUBLIC-IP>" ./run-all-tests.sh
```

---

## Test Suites Breakdown & Invariants

#### 1. `tests/backend/test_api.py`

- **ALB Health Probe:** Validates HTTP 200 and `{"status": "ok"}` contract for AWS Target Groups.
- **Product Catalog Listing:** Verifies public endpoints return paginated active catalog items.
- **Anonymous Mutation Guards:** Confirms unauthorized users cannot write to protected catalog APIs (expecting `401`, `403`, or `405`).
- **Atomic Checkout & Tax Accrual:** Ensures that successful order placement simultaneously calculates the 5% tax rule on taxable items only and atomically decrements product inventory.

#### 2. `tests/backend/test_checkout.py`

- **Stock Decrementing:** Verifies exact inventory count deduction on order completion.
- **Transaction Rollback on Card Decline:** Simulates declined payment cards (`4000000000000002`), asserting:
  - An HTTP `402 Payment Required` response is returned.
  - The transaction aborts with zero orphaned order records created.
  - Inventory quantities remain unchanged.

#### 3. `tests/backend/test_payments.py`

- **Card Authorisation Logic:** Unit tests covering card brand detection (`visa`, `mastercard`), expiration validation, and custom exception handling (`card_declined`, `insufficient_funds`, `expired_card`).
- **Tax Calculation Engine:** Verifies arithmetic rounding on mixed carts (e.g., taxable hoodie vs. non-taxable lanyard).

#### 4. `tests/backend/test_rbac.py`

- **Multi-Tenant Scoping:** Verifies Tenant Isolation where Merchant A attempting to access `/api/manage/merchants/<Merchant_B_ID>/` receives an HTTP `404 Not Found` (or `403 Forbidden`) instead of leaking store metadata.
- **Role Hierarchy:** Confirms anonymous users, standard members, merchants, and admins only access their respective permission scopes.

#### 5. `tests/smoke/test_smoke.py`

- **Liveness Probe:** Validates HTTP `/healthz/`.
- **Readiness Probe:** Validates HTTP `/readyz/` to ensure PostgreSQL connections and AWS S3 media bucket storage adapters are operational.
- **Build Identity:** Verifies that `/api/version/` reports the anticipated Git commit SHA deployed by CI/CD.
- **S3 Media Linkages:** Checks that product images in the catalog resolve to the expected S3 storage bucket URL patterns.

---

## Reports & Artifacts

All backend test runs output machine-readable reports into the `reports/` directory:

- **`reports/junit-backend.xml`:** JUnit-formatted test execution report for CI dashboards.
- **`reports/coverage-backend.xml`:** Cobertura XML coverage report for reporting tools.
- **`reports/coverage-html/index.html`:** Interactive HTML line-by-line coverage report.

#### Open the coverage report locally:

```bash
# Linux
xdg-open reports/coverage-html/index.html

# macOS
open reports/coverage-html/index.html
```

---

## Troubleshooting & Common Pitfalls

#### 1. Out-of-Memory (OOM) Errors on Small EC2 Instances (t2.micro / t3.micro)

Small EC2 instances have 1 GB of RAM. Compiling dependencies or running headless Chromium will trigger Linux OOM kills `(Exit code 137)`.

**Remedy**: Configure a 2 GB swapfile before running tests:

```bash
if [ $(free -m | awk '/Swap:/ {print $2}') -eq 0 ]; then
  sudo dd if=/dev/zero of=/swapfile bs=128M count=16
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  grep -q "/swapfile" /etc/fstab || echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
fi
```

#### 2. NPM or Playwright Installation Hangs / Crashes

If `npm install -D @playwright/test ...` or `npx playwright install chromium` terminates with `ENOMEM` or hangs:

1. Ensure the swapfile above has been activated (`free -h`).
2. Run `npm` with limited concurrent workers:

```bash
npm install -D @playwright/test vitest vite @vitejs/plugin-vue jsdom @vitest/coverage-v8 pinia axios
```
