from rest_framework.test import APITestCase
from rest_framework import status


class HealthCheckSmokeTests(APITestCase):

    def test_healthz_reports_ok(self):
        response = self.client.get("/healthz/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["status"], "ok")

    def test_readyz_reports_database_and_storage_ok(self):
        response = self.client.get("/readyz/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["database"], "ok")
        self.assertEqual(response.data["storage"], "ok")

    def test_version_endpoint_reports_a_build(self):
        response = self.client.get("/api/version/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("version", response.data)
        self.assertIn("commit", response.data)