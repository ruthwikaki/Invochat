
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0];

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', 'TestPass123!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
}

test.describe('Component Interaction Tests', () => {

  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test('should open and close the Alert Center', async ({ page }) => {
    const alertButton = page.locator('button[aria-label="Alerts"]');
    const popoverContent = page.locator('.popover-content');

    await expect(popoverContent).not.toBeVisible();
    
    await alertButton.click();
    await expect(popoverContent).toBeVisible();
    await expect(popoverContent.getByText('Notifications')).toBeVisible();

    // Click outside to close
    await page.locator('body').click({ position: { x: 0, y: 0 } });
    await expect(popoverContent).not.toBeVisible();
  });

  test('should navigate between pages using pagination controls', async ({ page }) => {
    await page.goto('/inventory');
    await page.waitForURL('/inventory');

    const nextButton = page.locator('button:has-text("Next")');
    const prevButton = page.locator('button:has-text("Previous")');

    // Check if pagination is even needed
    if (!await nextButton.isVisible()) {
        console.log('Skipping pagination test: Not enough data for multiple pages.');
        return;
    }

    const firstRowText = await page.locator('table > tbody > tr').first().innerText();
    
    await nextButton.click();
    await page.waitForURL('**/inventory?page=2');
    await page.waitForLoadState('networkidle');

    const secondPageFirstRowText = await page.locator('table > tbody > tr').first().innerText();
    expect(secondPageFirstRowText).not.toEqual(firstRowText);

    await prevButton.click();
    await page.waitForURL('**/inventory?page=1');
    await page.waitForLoadState('networkidle');

    const firstPageFirstRowText = await page.locator('table > tbody > tr').first().innerText();
    expect(firstPageFirstRowText).toEqual(firstRowText);
  });
});
