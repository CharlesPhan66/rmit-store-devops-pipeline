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
