from rest_framework.test import APITestCase
from rest_framework import status
from apps.catalog.models import Product, Category, Brand


class ShopEndpointIntegrationTests(APITestCase):

    def setUp(self):
        self.category = Category.objects.create(name="T-Shirts", slug="t-shirts")
        self.brand = Brand.objects.create(name="RMIT Official", slug="rmit-official")
        self.product = Product.objects.create(
            name="RMIT Test Tee",
            slug="rmit-test-tee",
            sku="TEST-001",
            price="29.95",
            quantity=10,
            is_active=True,
            taxable=True,
            brand=self.brand,
        )
        self.product.categories.set([self.category])

    def test_shop_endpoint_returns_200(self):
        response = self.client.get("/api/products/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_shop_endpoint_returns_seeded_product(self):
        response = self.client.get("/api/products/")
        names = [p["name"] for p in response.data["results"]]
        self.assertIn("RMIT Test Tee", names)

    def test_inactive_product_never_appears(self):
        self.product.is_active = False
        self.product.save()

        response = self.client.get("/api/products/")
        names = [p["name"] for p in response.data["results"]]
        self.assertNotIn("RMIT Test Tee", names)