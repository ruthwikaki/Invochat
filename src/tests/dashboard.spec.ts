import { test, expect } from '@playwright/test';

test.describe('Dashboard Page', () => {
    test.beforeEach(async ({ page }) => {
        await page.goto('/dashboard');
    });

    test('should load all dashboard cards', async ({ page }) => {
        await expect(page.getByText('Total Revenue')).toBeVisible();
        await expect(page.getByText('Total Orders')).toBeVisible();
        await expect(page.getByText('New Customers')).toBeVisible();
        await expect(page.getByText('Dead Stock Value')).toBeVisible();
        await expect(page.getByText('Sales Overview')).toBeVisible();
        await expect(page.getByText('Top Selling Products')).toBeVisible();
        await expect(page.getByText('Inventory Value Summary')).toBeVisible();
    });

    test('should have quick action buttons that navigate', async ({ page }) => {
        await page.getByRole('button', { name: 'Import Data' }).click();
        await expect(page).toHaveURL(/.*import/);
        await page.goBack();

        await page.getByRole('button', { name: 'Check Reorders' }).click();
        await expect(page).toHaveURL(/.*reordering/);
    });

});
