// RMIT University Vietnam
// Course: COSC2767|COSC2805 Systems Deployment and Operations
// Semester: 2026B
// Assessment: Assignment 2
// Author: Le Nguyen Thanh Trung - 4123479
// Created date: 22/08/2026
// Last modified: 11/09/2026
// Acknowledgement: None

import { describe, it, expect, beforeEach } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { useCartStore } from "@/stores/cart";

describe("Cart Store", () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    localStorage.clear();
  });

  it("correctly merges duplicate products into existing quantity", () => {
    const cart = useCartStore();
    // inventory >= 50 allows purchasing up to 5 items per rationing rules
    const product = {
      id: 101,
      name: "RMIT Hoodie",
      price: 25.99,
      quantity: 50,
    };

    expect(cart.items.length).toBe(0);

    cart.add(product, 2);
    expect(cart.items.length).toBe(1);
    expect(cart.items[0].quantity).toBe(2);

    cart.add(product, 1);
    expect(cart.items.length).toBe(1);
    expect(cart.items[0].quantity).toBe(3);
  });

  it("clamps added quantity against total available inventory stock", () => {
    const cart = useCartStore();
    const product = { id: 102, name: "Limited Cap", price: 15.0, quantity: 50 };

    cart.add(product, 2);
    expect(cart.items[0].quantity).toBe(2);

    // Clamps against the max purchase quantity cap of 5 for inventory <= 100
    cart.setQuantity(102, 10);
    expect(cart.items[0].quantity).toBe(5);
  });

  it("computes subtotal accurately", () => {
    const cart = useCartStore();
    cart.add({ id: 1, price: 44.95, quantity: 50 }, 1);
    cart.add({ id: 2, price: 27.95, quantity: 50 }, 1);

    expect(cart.subtotal).toBeCloseTo(72.9, 2);
  });
});
