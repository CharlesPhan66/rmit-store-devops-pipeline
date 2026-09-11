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
    pytest.mark.skipif(not BASE, reason="BASE_URL is not set yet"),
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


def test_shop_endpoint_responds():
    """The catalogue endpoint works end to end: it reaches the database and
    returns a well-formed page envelope.

    Deliberately says nothing about how many products came back. An empty
    catalogue is a fact about the DATA, not about the deployment, and a freshly
    built production database is legitimately empty - only staging is seeded.
    """
    response = requests.get(f"{BASE}/api/products/", timeout=TIMEOUT)
    assert response.status_code == 200
    assert "count" in response.json(), response.text


@pytest.mark.skipif(
    not os.environ.get("EXPECT_CATALOGUE"),
    reason="Only an environment that gets seeded is expected to hold products",
)
def test_shop_returns_products():
    """Staging only, gated by EXPECT_CATALOGUE.

    This is what proves seed_demo actually ran and that the images it uploaded
    are readable back out of S3.
    """
    response = requests.get(f"{BASE}/api/products/", timeout=TIMEOUT)
    assert response.json()["count"] > 0, "seed_demo did not populate the catalogue"
