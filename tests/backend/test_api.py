import pytest
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status
from django.contrib.auth import get_user_model
from apps.catalog.models import Product, Category, Brand
from apps.accounts.models import User, Role
from apps.merchants.models import Merchant
from apps.orders.models import Order

User = get_user_model()

# Selected by the pipeline's `pytest -m "unit or integration"` Test stage.
pytestmark = pytest.mark.integration


@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def admin_user(db):
    return User.objects.create_superuser(
        email="admin@rmit.edu.au",
        password="AdminPass2767!",
        first_name="Admin",
        last_name="User",
        role=Role.ADMIN,
    )


@pytest.fixture
def member_user(db):
    return User.objects.create_user(
        email="member@rmit.edu.au",
        password="MemberPass2767!",
        first_name="John",
        last_name="Shopper",
        role=Role.MEMBER,
    )


@pytest.fixture
def sample_catalog(db):
    brand = Brand.objects.create(name="Campus Gear", slug="campus-gear", is_active=True)
    category = Category.objects.create(name="Apparel", slug="apparel", is_active=True)

    product_taxable = Product.objects.create(
        sku="HOODIE-001",
        name="RMIT Hoodie",
        slug="rmit-hoodie",
        price=44.95,
        quantity=10,
        brand=brand,
        is_active=True,
        taxable=True,
    )
    product_taxable.categories.add(category)

    product_non_taxable = Product.objects.create(
        sku="LANYARD-001",
        name="RMIT Lanyard",
        slug="rmit-lanyard",
        price=27.95,
        quantity=5,
        brand=brand,
        is_active=True,
        taxable=False,
    )
    product_non_taxable.categories.add(category)

    return {"product_1": product_taxable, "product_2": product_non_taxable}


@pytest.mark.django_db
def test_alb_health_probe(api_client):
    response = api_client.get("/healthz/")
    assert response.status_code == status.HTTP_200_OK
    assert response.json() == {"status": "ok"}


@pytest.mark.django_db
def test_get_products_list(api_client, sample_catalog):
    response = api_client.get("/api/products/")
    assert response.status_code == status.HTTP_200_OK
    assert len(response.data["results"]) >= 1
    names = [p["name"] for p in response.data["results"]]
    assert "RMIT Hoodie" in names
    assert "RMIT Lanyard" in names


@pytest.mark.django_db
def test_anonymous_user_restricted_from_admin_mutation(api_client):
    response = api_client.post(
        "/api/products/", {"name": "Hacked Item", "sku": "HACK-01", "price": 1.00}
    )
    assert response.status_code in [
        status.HTTP_401_UNAUTHORIZED,
        status.HTTP_403_FORBIDDEN,
        status.HTTP_405_METHOD_NOT_ALLOWED,
    ]


@pytest.mark.django_db
def test_product_detail(api_client, sample_catalog):
    product = sample_catalog["product_1"]
    response = api_client.get(f"/api/products/{product.slug}/")

    assert response.status_code == status.HTTP_200_OK
    assert response.data["name"] == "RMIT Hoodie"


@pytest.mark.django_db
def test_shop_endpoint_returns_products(api_client, sample_catalog):
    response = api_client.get(reverse("product-list"))

    assert response.status_code == status.HTTP_200_OK
    assert len(response.data["results"]) > 0


@pytest.mark.django_db
def test_checkout_atomic_decrement_and_tax(api_client, member_user, sample_catalog):
    api_client.force_authenticate(user=member_user)

    payload = {
        "items": [
            {"product": sample_catalog["product_1"].id, "quantity": 1},
            {"product": sample_catalog["product_2"].id, "quantity": 1},
        ],
        "payment": {
            "number": "4242424242424242",
            "exp_month": 12,
            "exp_year": 2028,
            "cvc": "123",
            "name_on_card": "John Shopper",
        },
    }

    response = api_client.post("/api/orders/", payload, format="json")
    assert response.status_code == status.HTTP_201_CREATED
    assert float(response.data["subtotal"]) == 72.90
    assert float(response.data["total_tax"]) == 2.25
    assert float(response.data["total"]) == 75.15
    assert (
        response.data["payment_status"] == "paid" or response.data["status"] == "paid"
    )

    p1 = Product.objects.get(id=sample_catalog["product_1"].id)
    p2 = Product.objects.get(id=sample_catalog["product_2"].id)
    assert p1.quantity == 9
    assert p2.quantity == 4


@pytest.mark.django_db
def test_declined_payment_leaves_no_order_and_retains_stock(
    api_client, member_user, sample_catalog
):
    api_client.force_authenticate(user=member_user)

    payload = {
        "items": [{"product": sample_catalog["product_1"].id, "quantity": 2}],
        "payment": {
            "number": "4000000000000002",
            "exp_month": 12,
            "exp_year": 2028,
            "cvc": "123",
        },
    }

    response = api_client.post("/api/orders/", payload, format="json")
    assert response.status_code in [
        status.HTTP_400_BAD_REQUEST,
        status.HTTP_402_PAYMENT_REQUIRED,
    ]
    assert Order.objects.count() == 0

    p1 = Product.objects.get(id=sample_catalog["product_1"].id)
    assert p1.quantity == 10
