# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Le Nguyen Thanh Trung - 4123479
# Created date: 22/08/2026
# Last modified: 11/09/2026
# Acknowledgement: None

import pytest
from rest_framework import status
from rest_framework.test import APIClient
from django.contrib.auth import get_user_model
from apps.catalog.models import Product, Category, Brand
from apps.orders.models import Order

User = get_user_model()

# Selected by the pipeline's `pytest -m "unit or integration"` Test stage.
pytestmark = pytest.mark.integration


@pytest.fixture
def member_user(db):
    return User.objects.create_user(
        email="member@rmit.edu.au", password="Pass", role="member"
    )


@pytest.fixture
def taxable_item(db):
    category = Category.objects.create(name="Gear", slug="gear", is_active=True)
    brand = Brand.objects.create(name="RMIT", slug="rmit", is_active=True)
    product = Product.objects.create(
        sku="TAX-ITEM-001",
        name="Taxable Product",
        slug="taxable-product",
        price=50.00,
        quantity=10,
        taxable=True,
        is_active=True,
        brand=brand,
    )
    product.categories.add(category)
    return product


@pytest.mark.django_db
class TestAtomicCheckoutIntegration:

    def test_successful_checkout_decrements_stock_once(self, member_user, taxable_item):
        client = APIClient()
        client.force_authenticate(user=member_user)
        initial_stock = taxable_item.quantity

        payload = {
            "items": [{"product": taxable_item.id, "quantity": 2}],
            "payment": {
                "number": "4242424242424242",
                "exp_month": 12,
                "exp_year": 2028,
                "cvc": "123",
            },
        }

        response = client.post("/api/orders/", payload, format="json")
        assert response.status_code == status.HTTP_201_CREATED

        taxable_item.refresh_from_db()
        assert taxable_item.quantity == initial_stock - 2

    def test_declined_card_triggers_rollback_no_orphaned_data(
        self, member_user, taxable_item
    ):
        client = APIClient()
        client.force_authenticate(user=member_user)
        initial_stock = taxable_item.quantity
        initial_orders = Order.objects.count()

        payload = {
            "items": [{"product": taxable_item.id, "quantity": 2}],
            "payment": {
                "number": "4000000000000002",
                "exp_month": 12,
                "exp_year": 2028,
                "cvc": "123",
            },
        }

        response = client.post("/api/orders/", payload, format="json")
        assert response.status_code == status.HTTP_402_PAYMENT_REQUIRED

        assert Order.objects.count() == initial_orders
        taxable_item.refresh_from_db()
        assert taxable_item.quantity == initial_stock
