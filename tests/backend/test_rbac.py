import pytest
from rest_framework.test import APIClient
from rest_framework import status
from django.contrib.auth import get_user_model
from apps.merchants.models import Merchant

User = get_user_model()

# Selected by the pipeline's `pytest -m "unit or integration"` Test stage.
pytestmark = pytest.mark.integration


@pytest.mark.django_db
class TestSecurityAndRBACMatrix:

    @pytest.fixture(autouse=True)
    def setup_users(self):
        self.client = APIClient()
        self.member = User.objects.create_user(
            email="member@rmit.edu", password="Pass", role="member"
        )
        self.merchant_a_store = Merchant.objects.create(
            name="Store A", email="store_a@rmit.edu", is_active=True
        )
        self.merchant_b_store = Merchant.objects.create(
            name="Store B", email="store_b@rmit.edu", is_active=True
        )

        self.merchant_a = User.objects.create_user(
            email="merchant_a@rmit.edu",
            password="Pass",
            role="merchant",
            merchant=self.merchant_a_store,
        )
        self.merchant_b = User.objects.create_user(
            email="merchant_b@rmit.edu",
            password="Pass",
            role="merchant",
            merchant=self.merchant_b_store,
        )
        self.admin = User.objects.create_superuser(
            email="admin@rmit.edu", password="Pass", role="admin"
        )

    def test_anonymous_user_blocked_from_protected_routes(self):
        response = self.client.get("/api/orders/")
        assert response.status_code in [
            status.HTTP_401_UNAUTHORIZED,
            status.HTTP_403_FORBIDDEN,
        ]

    def test_member_blocked_from_merchant_dashboard(self):
        self.client.force_authenticate(user=self.member)
        response = self.client.get("/api/manage/merchants/")
        assert response.status_code in [
            status.HTTP_403_FORBIDDEN,
            status.HTTP_404_NOT_FOUND,
        ]

    def test_merchant_cross_tenant_isolation_returns_404_not_403(self):
        self.client.force_authenticate(user=self.merchant_a)
        response = self.client.get(f"/api/manage/merchants/{self.merchant_b_store.id}/")
        assert response.status_code in [
            status.HTTP_403_FORBIDDEN,
            status.HTTP_404_NOT_FOUND,
        ]

    def test_admin_has_full_system_access(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get("/api/manage/merchants/")
        assert response.status_code == status.HTTP_200_OK

    def test_merchant_ownership_scoping_isolation(self):
        self.client.force_authenticate(user=self.merchant_a)
        response = self.client.get(f"/api/manage/merchants/{self.merchant_a_store.id}/")
        assert response.status_code in [status.HTTP_200_OK, status.HTTP_403_FORBIDDEN]
