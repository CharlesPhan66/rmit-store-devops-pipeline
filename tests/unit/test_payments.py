"""Unit test for payments. No DB, no network."""

from datetime import date

import pytest

from apps.orders.payments import (
    APPROVE_CARDS,
    DECLINE_CARDS,
    PaymentDeclined,
    authorise,
    card_brand,
    cvc_length_for,
    has_expired,
    luhn_valid,
    normalise,
)

pytestmark = pytest.mark.unit

VISA = "4242424242424242"
AMEX = "378282246310005"


class TestNormalise:
    def test_strips_spaces_and_dashes(self):
        assert normalise("4242 4242-4242 4242") == VISA

    def test_drops_letters(self):
        assert normalise("4242abc4242") == "42424242"


class TestLuhn:
    def test_accepts_every_documented_approve_card(self):
        for number in APPROVE_CARDS:
            assert luhn_valid(number), number

    def test_accepts_every_documented_decline_card(self):
        for number in DECLINE_CARDS:
            assert luhn_valid(number), number

    def test_rejects_transposed_digits(self):
        assert not luhn_valid("4242424242424224")

    def test_rejects_too_short(self):
        assert not luhn_valid("4242")

    def test_rejects_non_digits(self):
        assert not luhn_valid("not-a-card")


class TestBrand:
    @pytest.mark.parametrize(
        "number,expected",
        [
            (VISA, "visa"),
            ("5555555555554444", "mastercard"),
            ("2221000000000009", "mastercard"),
            (AMEX, "amex"),
            ("371449635398431", "amex"),
            ("3530111333300000", "jcb"),
            ("6011111111111117", "discover"),
            ("9999999999999999", "card"),
            ("", "card"),
        ],
    )
    def test_brand_from_prefix(self, number, expected):
        assert card_brand(number) == expected

    def test_every_approve_card_maps_to_its_documented_brand(self):
        for number, brand in APPROVE_CARDS.items():
            assert card_brand(number) == brand


class TestCvcLength:
    def test_amex_wants_four(self):
        assert cvc_length_for(AMEX) == 4

    def test_everyone_else_wants_three(self):
        assert cvc_length_for(VISA) == 3


class TestExpiry:
    def test_good_until_last_day_of_month(self):
        assert not has_expired(6, 2026, today=date(2026, 6, 30))

    def test_expired_the_month_after(self):
        assert has_expired(6, 2026, today=date(2026, 7, 1))

    def test_future_year_is_fine(self):
        assert not has_expired(1, 2030, today=date(2026, 6, 15))


class TestAuthorise:
    def test_approved_card_returns_charge_without_the_number(self):
        charge = authorise(VISA, 12, 2030, "123", "75.15")

        assert charge.reference.startswith("ch_")
        assert charge.brand == "visa"
        assert charge.last4 == "4242"
        assert charge.amount == "75.15"
        assert VISA not in repr(charge)

    @pytest.mark.parametrize("number,expected_code", [
        ("4000000000000002", "card_declined"),
        ("4000000000009995", "insufficient_funds"),
        ("4000000000000069", "expired_card"),
        ("4000000000000127", "incorrect_cvc"),
        ("4000000000000119", "processing_error"),
    ])
    def test_each_decline_card_gives_its_own_code(self, number, expected_code):
        with pytest.raises(PaymentDeclined) as exc:
            authorise(number, 12, 2030, "123", "10.00")
        assert exc.value.decline_code == expected_code

    def test_declined_is_402_not_400(self):
        with pytest.raises(PaymentDeclined) as exc:
            authorise("4000000000000002", 12, 2030, "123", "10.00")
        assert exc.value.status_code == 402

    def test_expired_card_is_declined(self):
        with pytest.raises(PaymentDeclined) as exc:
            authorise(VISA, 1, 2020, "123", "10.00")
        assert exc.value.decline_code == "expired_card"

    def test_amex_with_three_digit_cvc_is_declined(self):
        with pytest.raises(PaymentDeclined) as exc:
            authorise(AMEX, 12, 2030, "123", "10.00")
        assert exc.value.decline_code == "incorrect_cvc"

    def test_amex_with_four_digit_cvc_is_approved(self):
        assert authorise(AMEX, 12, 2030, "1234", "10.00").brand == "amex"
