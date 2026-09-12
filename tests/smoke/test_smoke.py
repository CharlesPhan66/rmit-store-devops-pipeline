# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Le Nguyen Thanh Trung - 4123479
# Created date: 22/08/2026
# Last modified: 11/09/2026
# Acknowledgement: None

import os
import requests
import pytest

TARGET_URL = os.getenv("TARGET_URL", "http://127.0.0.1").rstrip("/")
EXPECTED_COMMIT = os.getenv("EXPECTED_GIT_COMMIT", "skip")


@pytest.mark.smoke
class TestDeploymentSmokeProbes:
    def test_liveness_probe_healthz(self):
        """Liveness check: process is alive and responds without touching state."""
        resp = requests.get(f"{TARGET_URL}/healthz/", timeout=10)
        assert resp.status_code == 200
        assert resp.json().get("status") == "ok"

    def test_readiness_probe_readyz(self):
        """Readiness check: PostgreSQL connection and S3 media storage must be fully operational."""
        resp = requests.get(f"{TARGET_URL}/readyz/", timeout=10)
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("database") == "ok", f"Database is down: {data}"
        assert data.get("storage") == "ok", f"S3 Media storage is down: {data}"

    def test_build_version_probe(self):
        """Build check: verify the running commit matches the deployed build."""
        resp = requests.get(f"{TARGET_URL}/api/version/", timeout=10)
        assert resp.status_code == 200
        data = resp.json()
        assert "version" in data
        assert "commit" in data

        if EXPECTED_COMMIT != "skip":
            assert (
                data["commit"] == EXPECTED_COMMIT
            ), f"Version mismatch! Target is running {data['commit']}, expected {EXPECTED_COMMIT}"

    def test_catalog_endpoint_integrity(self):
        """API sanity check: ensure catalog returns products and images resolve to S3."""
        resp = requests.get(f"{TARGET_URL}/api/products/", timeout=10)
        assert resp.status_code == 200
        data = resp.json()
        assert data.get("count", 0) > 0, "No products found in catalog response"

        first_product = data["results"][0]
        assert "image_url" in first_product

        # Check across multiple common S3 domain formats
        valid_s3_patterns = [
            "s3.amazonaws.com",
            "s3.us-east-1.amazonaws.com",
            "rmit-store-media",
        ]
        assert any(
            pattern in first_product["image_url"] for pattern in valid_s3_patterns
        ), f"Image URL does not originate from S3 storage: {first_product['image_url']}"
