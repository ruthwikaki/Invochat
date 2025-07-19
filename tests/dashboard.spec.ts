
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Dashboard', () => {

  test.beforeEach(async ({ page, context }) => {
    // Log in before each test
    await login(page, context);
  });

  test('should load and display key dashboard components', async ({ page }) => {
    // After login, we should be on the dashboard
    await expect(page).toHaveURL('/dashboard');
    await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible();

    // Check for the main analytics stat cards
    await expect(page.getByRole('heading', { name: 'Total Revenue' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Total Sales' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'New Customers' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Dead Stock Value' })).toBeVisible();

    // Check for the chart and list cards
    await expect(page.getByRole('heading', { name: 'Sales Overview' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Top Selling Products' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Inventory Value Summary' })).toBeVisible();
    
    // Check that the AI morning briefing card is present
    await expect(page.getByRole('heading', { name: /Good morning|Good afternoon|Good evening/ })).toBeVisible();
  });

});
