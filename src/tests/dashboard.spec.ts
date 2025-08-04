import { test, expect } from '@playwright/test';

test.describe('Dashboard Page', () => {
    test.beforeEach(async ({ page }) => {
        // This assumes a global setup handles login.
        // For standalone tests, login steps would be here.
        await page.goto('/login');
        await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'test@example.com');
        await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'password');
        await page.click('button[type="submit"]');
        await page.waitForURL('/dashboard');
    });

    test('should load all dashboard cards and validate key metrics', async ({ page }) => {
        await expect(page.getByText('Total Revenue')).toBeVisible();
        await expect(page.getByText('Total Orders')).toBeVisible();
        await expect(page.getByText('New Customers')).toBeVisible();
        await expect(page.getByText('Dead Stock Value')).toBeVisible();
        await expect(page.getByText('Sales Overview')).toBeVisible();
        await expect(page.getByText('Top Selling Products')).toBeVisible();
        await expect(page.getByText('Inventory Value Summary')).toBeVisible();

        // Data Validation
        const totalRevenueCard = page.locator('.card', { hasText: 'Total Revenue' });
        const totalOrdersCard = page.locator('.card', { hasText: 'Total Orders' });

        const revenueText = await totalRevenueCard.locator('.text-3xl').innerText();
        const ordersText = await totalOrdersCard.locator('.text-3xl').innerText();

        // Parse currency and numbers
        const revenueValue = parseFloat(revenueText.replace(/[^0-9.-]+/g,""));
        const ordersValue = parseInt(ordersText.replace(/,/g, ''), 10);
        
        console.log(`Validated Metrics - Revenue: ${revenueValue}, Orders: ${ordersValue}`);

        // Assert that the numbers are plausible (not zero, given test data)
        expect(revenueValue).toBeGreaterThan(0);
        expect(ordersValue).toBeGreaterThan(0);
    });

    test('should have quick action buttons that navigate', async ({ page }) => {
        await page.getByRole('button', { name: 'Import Data' }).click();
        await expect(page).toHaveURL(/.*import/);
        await page.goBack();

        await page.getByRole('button', { name: 'Check Reorders' }).click();
        await expect(page).toHaveURL(/.*reordering/);
    });

});
