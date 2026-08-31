from decimal import Decimal
from django.test import TestCase
from apps.orders.services import money, tax_for


class MoneyRoundingTests(TestCase):

    def test_rounds_down_below_half_cent(self):
        self.assertEqual(money(Decimal("10.001")), Decimal("10.00"))

    def test_rounds_up_at_half_cent(self):
        self.assertEqual(money(Decimal("10.005")), Decimal("10.01"))

    def test_already_exact_value_unchanged(self):
        self.assertEqual(money(Decimal("44.95")), Decimal("44.95"))


class TaxCalculationTests(TestCase):

    def test_non_taxable_line_has_zero_tax(self):
        result = tax_for(Decimal("44.95"), taxable=False)
        self.assertEqual(result, Decimal("0.00"))

    def test_taxable_line_applies_configured_rate(self):
        # Matches the README's worked example: 5% of $44.95 = $2.25 (rounded)
        result = tax_for(Decimal("44.95"), taxable=True)
        self.assertEqual(result, Decimal("2.25"))

    def test_taxable_zero_amount_is_zero_tax(self):
        result = tax_for(Decimal("0.00"), taxable=True)
        self.assertEqual(result, Decimal("0.00"))