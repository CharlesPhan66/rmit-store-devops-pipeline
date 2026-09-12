# RMIT University Vietnam
# Course: COSC2767|COSC2805 Systems Deployment and Operations
# Semester: 2026B
# Assessment: Assignment 2
# Author: Le Nguyen Thanh Trung - 4123479
# Created date: 22/08/2026
# Last modified: 11/09/2026
# Acknowledgement: None

import pytest
from decimal import Decimal
from django.test import TestCase

from apps.orders.payments import authorise, PaymentDeclined
from apps.orders.services import money, tax_for

# Selected by the pipeline's `pytest -m "unit or integration"` Test stage.
pytestmark = pytest.mark.integration


def calculate_order_total(items, tax_rate=Decimal("0.05")):
    """Local test helper for calculating order total using server's tax rounding rules."""
    subtotal = sum((item["price"] for item in items), Decimal("0.00"))
    taxable_subtotal = sum(
        (item["price"] for item in items if item.get("taxable", False)), Decimal("0.00")
    )
    tax = money(taxable_subtotal * Decimal(str(tax_rate)))
    total = subtotal + tax
    return subtotal, tax, total


class PaymentProcessorTests(TestCase):
    def test_approved_visa_card(self):
        """Card beginning with 4242 yields approval and correct metadata."""
        charge = authorise(
            number="4242424242424242",
            exp_month=12,
            exp_year=2028,
            cvc="123",
            amount=Decimal("50.00"),
        )
        self.assertEqual(charge.brand, "visa")
        self.assertEqual(charge.last4, "4242")

    def test_approved_mastercard(self):
        """Card beginning with 5555 yields approval and Mastercard brand."""
        charge = authorise(
            number="5555555555554444",
            exp_month=12,
            exp_year=2028,
            cvc="123",
            amount=Decimal("50.00"),
        )
        self.assertEqual(charge.brand, "mastercard")
        self.assertEqual(charge.last4, "4444")

    def test_declined_card(self):
        """Card ending in 0002 triggers explicit card_declined failure."""
        with self.assertRaises(PaymentDeclined) as cm:
            authorise(
                number="4000000000000002",
                exp_month=12,
                exp_year=2028,
                cvc="123",
                amount=Decimal("50.00"),
            )
        self.assertEqual(cm.exception.decline_code, "card_declined")

    def test_insufficient_funds(self):
        """Card ending in 9995 triggers explicit insufficient_funds failure."""
        with self.assertRaises(PaymentDeclined) as cm:
            authorise(
                number="4000000000009995",
                exp_month=12,
                exp_year=2028,
                cvc="123",
                amount=Decimal("50.00"),
            )
        self.assertEqual(cm.exception.decline_code, "insufficient_funds")

    def test_expired_card(self):
        """Expired card date (01/20) triggers explicit expired_card failure."""
        with self.assertRaises(PaymentDeclined) as cm:
            authorise(
                number="4242424242424242",
                exp_month=1,
                exp_year=2020,
                cvc="123",
                amount=Decimal("50.00"),
            )
        self.assertEqual(cm.exception.decline_code, "expired_card")

    def test_tax_calculation(self):
        """Asserts 5% tax is applied strictly to taxable line items."""
        items = [
            {"price": Decimal("44.95"), "taxable": True},
            {"price": Decimal("27.95"), "taxable": False},
        ]
        subtotal, tax, total = calculate_order_total(items, tax_rate=Decimal("0.05"))
        self.assertEqual(subtotal, Decimal("72.90"))
        self.assertEqual(tax, Decimal("2.25"))
        self.assertEqual(total, Decimal("75.15"))
