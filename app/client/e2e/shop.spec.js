import { test, expect } from '@playwright/test';

test('shop page renders real products from the API', async ({ page }) => {
  // Capture any browser console errors (e.g. CORS, JS exceptions, failed fetches)
  page.on('console', msg => console.log(`BROWSER CONSOLE [${msg.type()}]:`, msg.text()));
  page.on('pageerror', err => console.log('BROWSER PAGE ERROR:', err.message));
  page.on('requestfailed', req => console.log('REQUEST FAILED:', req.url(), req.failure()?.errorText));

  await page.goto('/shop');
  await page.waitForTimeout(3000); // give the API call time to resolve either way

  const bodyHTML = await page.locator('body').innerHTML();
  console.log('--- BODY HTML (first 2000 chars) ---');
  console.log(bodyHTML.slice(0, 2000));
  console.log('--- END BODY HTML ---');

  const productCards = page.locator('.product-card').first();
  await expect(productCards).toBeVisible({ timeout: 15000 });

  await expect(page.locator('body')).not.toContainText('error', { ignoreCase: true });
});

test('home page loads without a blank screen', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).toBeVisible();
  await expect(page).toHaveTitle(/.+/);
});