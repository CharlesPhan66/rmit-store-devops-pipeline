import { test, expect } from '@playwright/test';

test('shop page renders real products from the API', async ({ page }) => {
  await page.goto('/shop');

  const productCards = page.locator('.product-card').first();
  await expect(productCards).toBeVisible({ timeout: 15000 });

  await expect(page.locator('body')).not.toContainText('error', { ignoreCase: true });
});

test('home page loads without a blank screen', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).toBeVisible();
  await expect(page).toHaveTitle(/.+/);
});