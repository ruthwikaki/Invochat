
import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';

// Helper function to perform login
async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', process.env.TEST_USER_EMAIL || 'owner_stylehub@test.com');
    await page.fill('input[name="password"]', process.env.TEST_USER_PASSWORD || 'StyleHub2024!');
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
}

// Helper to parse currency string to number in cents
function parseCurrency(currencyString: string | null): number {
    if (!currencyString) return 0;
    return Math.round(parseFloat(currencyString.replace(/[^0-9.-]+/g, '')) * 100);
}

test.describe('Dashboard Page', () => {
    test.beforeEach(async ({ page }) => {
        await login(page);
    });

    test('should load all dashboard cards and validate key metrics', async ({ page }) => {
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

    test('dashboard revenue should be mathematically correct', async ({ page, request }) => {
        // 1. Get the ground truth from our test API endpoint
        const apiResponse = await request.get('/api/debug', {
            headers: {
                'Authorization': `Bearer ${process.env.TESTING_API_KEY}`
            }
        });
        expect(apiResponse.ok()).toBeTruthy();
        const groundTruth = await apiResponse.json();
        const expectedRevenueCents = groundTruth.totalRevenue;
        
        // Ensure we have some data to test against
        expect(expectedRevenueCents).toBeGreaterThan(0);

        // 2. Get the value displayed in the UI
        await page.goto('/dashboard');
        const totalRevenueCard = page.locator('.card', { hasText: 'Total Revenue' });
        await expect(totalRevenueCard).toBeVisible();
        const revenueText = await totalRevenueCard.locator('.text-3xl').innerText();
        
        // 3. Parse the UI value and compare
        const displayedRevenueCents = parseCurrency(revenueText);
        
        console.log(`Comparing Dashboard Revenue - Expected: ${expectedRevenueCents}, Displayed: ${displayedRevenueCents}`);

        // 4. Assert that the displayed value matches the ground truth from the database
        // We use toBeCloseTo to account for potential minor rounding differences.
        expect(displayedRevenueCents).toBeCloseTo(expectedRevenueCents, 1);
    });
});
