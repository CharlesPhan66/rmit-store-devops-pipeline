# Author: @CharlesPhan66 (Charles Phan)
# Last updated: 01/09/2026

# This file has one simple purpose: to test the deployment of the backend Django app.
# It is a smoke test that checks if the app is running and responding to requests
# It is a quick way to check if the app is deployed correctly
# It is not a comprehensive test of the app's functionality, if you are seeking to test the app's functionality, please refer to the unit and integration tests in the tests/ directory
# By this test, we can test important endpoints of the app, such as /healthz/, /readyz/, etc.
# Acknowledgement: https://youtu.be/EgpLj86ZHFQ?si=8uiKBs8HEfTJFM6U
import os
import pytest
import requests

# This use the real BASE_URL of the deployed app, which is set in the environment variable BASE_URL
BASE = os.environ.get("BASE_URL", "").rstrip("/")
# The GIT_SHA environment variable is set in the deployment pipeline, and it is used to check if the deployed app is the latest version
SHA = os.environ.get("GIT_SHA")
# 10s per request timeout
TIMEOUT = 10

pytestmark = [
    pytest.mark.smoke,
    pytest.mark.skipif(not BASE, reason="BASE_URL chua duoc dat"),
]

def test_healthz():
    response = requests.get(f"{BASE}/healthz/", timeout=TIMEOUT)
    assert response.status_code == 200


def test_readyz_dependencies_ok():
    response = requests.get(f"{BASE}/readyz/", timeout=TIMEOUT)
    assert response.status_code == 200, response.text


def test_version_matches_deployed_commit():
    response = requests.get(f"{BASE}/api/version/", timeout=TIMEOUT)
    assert response.status_code == 200
    if SHA:
        assert SHA in response.text, f"Version mismatch: {response.text}"


def test_shop_returns_products():
    response = requests.get(f"{BASE}/api/products/", timeout=TIMEOUT)
    assert response.status_code == 200
    assert response.json()["count"] > 0
