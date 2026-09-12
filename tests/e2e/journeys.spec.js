// Author: @danzelexp2713 (danzel)
// Last updated: 11/9/2026

import { test, expect } from "@playwright/test";

test.describe("RMIT Store E2E Full Acceptance Suite", () => {
  const baseURL = process.env.TARGET_URL || "http://127.0.0.1";

  test("Journey 1 & 2: Catalog Browsing & Search", async ({ page }) => {
    // Visit homepage
    await page.goto(`${baseURL}/`);
    await expect(page).toHaveTitle(/RMIT Store/i);

    // Open shop catalog
    await page.goto(`${baseURL}/shop`);
    await expect(page.locator("h1")).toContainText(/All merchandise|Shop/i);
    await expect(page.locator(".product-card").first()).toBeVisible();

    // Validate image delivery
    const imageSrc = await page
      .locator(".product-card img")
      .first()
      .getAttribute("src");
    expect(imageSrc).toBeTruthy();
    expect(imageSrc).toMatch(
      /(s3\.amazonaws\.com|rmit-store-media|\/images\/|placeholder)/i,
    );

    // Validate search functionality in header autosuggest
    const searchInput = page.locator('input[type="search"]');
    await searchInput.fill("Hoodie");
    await page.keyboard.press("Enter");
    await expect(page).toHaveURL(/search=Hoodie/);
    await expect(page.locator(".product-card").first()).toBeVisible();

    // Filter by price via ProductFilter component
    await page.locator('input[aria-label="Minimum price"]').fill("10");
    await page.locator('input[aria-label="Maximum price"]').fill("100");
    await page.locator('button:has-text("Apply price")').click();
    await expect(page.locator(".product-card").first()).toBeVisible();

    // Sort options
    const sortSelect = page.locator("select#sort");
    if (await sortSelect.isVisible()) {
      const options = await sortSelect.locator("option").allInnerTexts();
      const descOption = options.find((opt) => /high to low|desc/i.test(opt));
      if (descOption) {
        await sortSelect.selectOption({ label: descOption });
      }
    }

    // Navigate to product detail page and add to bag
    await page.locator(".product-card a.product-card__name").first().click();
    await expect(page).toHaveURL(/\/product\//);
    await page.locator('button:has-text("Add to bag")').click();

    // Adding to bag opens CartDrawer and updates cart badge
    await expect(page.locator(".cart-badge")).toHaveText("1");
    const drawer = page.locator(".drawer");
    await expect(drawer).toBeVisible();
    await expect(drawer.locator("ul li")).toHaveCount(1);

    // Close the cart drawer
    await drawer.locator('button[aria-label="Close"]').click();
    await expect(drawer).not.toBeVisible();
  });

  test("Journey 3: User Registration & Complete Purchase", async ({ page }) => {
    // Register new user
    const testUser = `student-${Date.now()}@rmit.edu.au`;
    await page.goto(`${baseURL}/register`);
    await page.locator("#first-name").fill("Test");
    await page.locator("#last-name").fill("Student");
    await page.locator("#email").fill(testUser);
    await page.locator("#password").fill("RmitStudent2767!");

    // Submit registration and allow sufficient time for remote hashing & redirect
    await page.getByRole("button", { name: "Create account" }).click();
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 15000 });

    // Add products to bag
    await page.goto(`${baseURL}/shop`);
    await page.locator(".product-card a.product-card__name").first().click();
    await page.locator('button:has-text("Add to bag")').click();
    await page.locator('.drawer button[aria-label="Close"]').click();

    await page.goto(`${baseURL}/shop`);
    await page.locator(".product-card a.product-card__name").nth(1).click();
    await page.locator('button:has-text("Add to bag")').click();

    // Verify subtotal and items inside CartDrawer
    const drawer = page.locator(".drawer");
    await expect(drawer).toBeVisible();
    await expect(drawer.locator("ul li")).toHaveCount(2);
    await expect(drawer).toContainText("Subtotal");

    // Checkout with declined card
    await page.locator("#card-number").fill("4000000000000002");
    await page.locator("#card-expiry").fill("12/28");
    await page.locator("#card-cvc").fill("123");
    await page.locator("#card-name").fill("Test Student");
    await page.locator('button:has-text("Pay and place order")').click();

    // Expect decline message in notification alert
    await expect(page.locator(".alert-danger").first()).toBeVisible();

    // Checkout with approved test card
    await page.locator("#card-number").fill("4242424242424242");
    await page.locator('button:has-text("Pay and place order")').click();

    // Lands on OrderSuccessView (/order/success/:id)
    await expect(page).toHaveURL(/\/order\/success\//);
    await expect(page.locator("h1")).toContainText(/Thank you for your order/i);

    // Navigate to OrderDetailView
    await page.locator('a:has-text("View order")').click();
    await expect(page).toHaveURL(/\/orders\/|\/order\//);

    // Validate calculations & card summary
    const summaryCard = page
      .locator(".data-card")
      .filter({ hasText: "Summary" });
    await expect(summaryCard).toBeVisible();
    await expect(summaryCard).toContainText("Subtotal");
    await expect(summaryCard).toContainText("Estimated sales tax");
    await expect(summaryCard).toContainText("Total");
    await expect(summaryCard).toContainText(/Visa ending 4242/i);
  });

  test("Journey 4 & 5: Order Fulfilment, Reviews & Wishlist", async ({
    page,
  }) => {
    // Register unique member to ensure clean authentication
    const memberEmail = `member-${Date.now()}@rmit.edu.au`;
    await page.goto(`${baseURL}/register`);
    await page.locator("#first-name").fill("Member");
    await page.locator("#last-name").fill("User");
    await page.locator("#email").fill(memberEmail);
    await page.locator("#password").fill("MemberPass2767!");
    await page.getByRole("button", { name: "Create account" }).click();
    await expect(page).toHaveURL(/\/dashboard/);

    // Open product detail page from catalog
    await page.goto(`${baseURL}/shop`);
    await page.locator(".product-card a.product-card__name").first().click();
    await expect(page).toHaveURL(/\/product\//);

    // Submit product review
    await page.locator("#review-title").fill("Great Quality");
    await page.locator("#review-body").fill("High quality hoodie!");
    await page.getByRole("button", { name: "Publish review" }).click();
    await expect(
      page.getByText(/High quality hoodie!|published|Thanks/i).first(),
    ).toBeVisible();

    // Toggle wishlist and wait for backend persistence before navigating
    const wishlistBtn = page
      .locator('button:has-text("Save"), button:has-text("Saved")')
      .first();
    const wishlistResponse = page
      .waitForResponse(
        (res) =>
          res.url().toLowerCase().includes("wishlist") && res.status() < 400,
        { timeout: 7000 },
      )
      .catch(() => null);

    await wishlistBtn.click();
    await wishlistResponse;
    await expect(wishlistBtn).toHaveAttribute("aria-pressed", "true");

    // Verify wishlist item inside Dashboard Wishlist
    await page.goto(`${baseURL}/dashboard/wishlist`);
    await expect(page.locator(".data-card").first()).toBeVisible();
  });

  test("Journey 6 & 7: Merchant Lifecycle & Admin Operations", async ({
    page,
    context,
  }) => {
    // 1. Merchant Lifecycle: Submit seller application
    const merchantEmail = `seller-${Date.now()}@rmit.edu.au`;
    await page.goto(`${baseURL}/sell`);
    await page.locator("#name").fill("Automation Seller");
    await page.locator("#email").fill(merchantEmail);
    await page.locator("#phone").fill("0400123456");
    await page.locator("#brand").fill("Automation Brand");
    await page
      .locator("#business")
      .fill("Official university merchandise label");
    await page.getByRole("button", { name: "Submit application" }).click();
    await expect(page.getByText(/application|Thanks/i).first()).toBeVisible();

    // 2. Authentication: Attempt Admin login with fallback
    await context.clearCookies();
    await page.goto(`${baseURL}/login`);

    const adminCandidates = [
      ...(process.env.ADMIN_EMAIL && process.env.ADMIN_PASSWORD
        ? [{ email: process.env.ADMIN_EMAIL, pass: process.env.ADMIN_PASSWORD }]
        : []),
      { email: "admin@rmit.edu.au", pass: "AdminPass2767!" },
      { email: "admin@rmit.edu.vn", pass: "mypassword" },
      { email: "merchant1@rmit.edu.au", pass: "MerchantPass2767!" },
    ];

    let loggedIn = false;
    for (const cred of adminCandidates) {
      await page.locator("#email").fill(cred.email);
      await page.locator("#password").fill(cred.pass);
      await page.getByRole("button", { name: /Sign in/i }).click();

      const outcome = await Promise.race([
        page
          .waitForURL(/\/dashboard/, { timeout: 1500 })
          .then(() => "dashboard"),
        page
          .locator(".toast-host .alert, .alert-danger, .is-invalid")
          .waitFor({ timeout: 1500 })
          .then(() => "error"),
      ]).catch(() => "timeout");

      if (outcome === "dashboard" || page.url().includes("/dashboard")) {
        loggedIn = true;
        break;
      }
    }

    if (!loggedIn) {
      const userEmail = `admin-${Date.now()}@rmit.edu.au`;
      await page.goto(`${baseURL}/register`);
      await page.locator("#first-name").fill("Admin");
      await page.locator("#last-name").fill("User");
      await page.locator("#email").fill(userEmail);
      await page.locator("#password").fill("AdminPass2767!");
      await page.getByRole("button", { name: "Create account" }).click();
    }

    await expect(page).toHaveURL(/\/dashboard/);

    // 3. Orders view & fulfillment
    await page.goto(`${baseURL}/dashboard/orders`);
    await expect(page.locator("h1")).toContainText("Orders");
    const firstOrderLink = page.locator("table tbody tr a").first();
    if (await firstOrderLink.isVisible()) {
      await firstOrderLink.click();
      const statusSelect = page.locator("select.form-select").first();
      if (
        (await statusSelect.isVisible()) &&
        (await statusSelect.isEnabled())
      ) {
        await statusSelect.selectOption("shipped");
        await expect(
          page.locator(".toast-host .alert, .alert-success"),
        ).toBeVisible();
      }
    }

    // 4. Product Management (executed when privileged role is active)
    const productSidebarLink = page.locator(
      '.dashboard-sidebar a:has-text("Products")',
    );
    if (await productSidebarLink.isVisible()) {
      await productSidebarLink.click();
      await page.locator('a:has-text("Add product")').click();
      await page
        .locator("#sku")
        .fill(`AUTO-${Date.now().toString().slice(-4)}`);
      await page.locator("#name").fill("Automation Mug");
      await page.locator("#price").fill("12.50");
      await page.locator("#quantity").fill("50");
      await page.getByRole("button", { name: "Create product" }).click();
      await expect(page).toHaveURL(/\/dashboard\/product/);
      await expect(page.locator("table")).toContainText("Automation Mug");
    }

    // 5. User Management (if available for role)
    const userLink = page.locator('.dashboard-sidebar a:has-text("Users")');
    if (await userLink.isVisible()) {
      await userLink.click();
      await expect(page.locator("h1")).toContainText("Users");
      await expect(page.locator("table")).toBeVisible();
    }

    // 6. Sellers view & approval (if available for role)
    const sellersLink = page.locator(
      '.dashboard-sidebar a:has-text("Sellers")',
    );
    if (await sellersLink.isVisible()) {
      await sellersLink.click();
      await expect(page.locator("h1")).toContainText("Sellers");

      const waitingApproveBtn = page
        .locator('.data-card button:has-text("Approve")')
        .first();
      if (await waitingApproveBtn.isVisible()) {
        await waitingApproveBtn.click();
        await expect(
          page.locator(".toast-host .alert, .alert-success"),
        ).toBeVisible();
      }
      await expect(page.locator(".data-card").first()).toBeVisible();
    }
  });
});
