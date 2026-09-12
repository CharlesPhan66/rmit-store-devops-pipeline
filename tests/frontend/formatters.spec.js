// RMIT University Vietnam
// Course: COSC2767|COSC2805 Systems Deployment and Operations
// Semester: 2026B
// Assessment: Assignment 2
// Author: Le Nguyen Thanh Trung - 4123479
// Created date: 22/08/2026
// Last modified: 11/09/2026
// Acknowledgement: None

import { describe, it, expect } from "vitest";
import { money, initial, shortDate } from "@/utils/format";

describe("Input & Visual Formatter Utilities", () => {
  it("formats monetary figures to AUD standard", () => {
    expect(money(75.15)).toBe("$75.15");
  });

  it("extracts uppercase initial from string", () => {
    expect(initial("rmit")).toBe("R");
  });

  it("formats short dates accurately", () => {
    expect(shortDate("2026-09-06")).toBe("6 Sept 2026");
  });
});
