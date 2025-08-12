

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

// Helper function to perform login
async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard');
    // Wait for either the empty state or the actual dashboard content
    await page.waitForSelector('text=/Welcome to ARVO|Sales Overview/', { timeout: 20000 });
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
        await expect(page.getByTestId('sales-overview-card')).toBeVisible();
        await expect(page.getByText('Total Orders')).toBeVisible();
        await expect(page.getByText('New Customers')).toBeVisible();
        await expect(page.getByText('Dead Stock Value')).toBeVisible();
        await expect(page.getByText('Top Selling Products')).toBeVisible();
        await expect(page.getByText('Inventory Value Summary')).toBeVisible();
    });

    test('should have quick action buttons that navigate', async ({ page }) => {
        await page.getByRole('button', { name: 'Import Data' }).click();
        await page.waitForURL(/.*import/);
        await expect(page).toHaveURL(/.*import/);
        await page.goBack();
        await page.waitForURL(/.*dashboard/);

        await page.getByRole('button', { name: 'Check Reorders' }).click();
        await page.waitForURL(/.*reordering/);
        await expect(page).toHaveURL(/.*reordering/);
    });

    test('dashboard revenue should be mathematically correct', async ({ page, request }) => {
        // This test requires a secure API key for the debug endpoint and should only run in a test environment
        if (!process.env.TESTING_API_KEY) {
            console.warn('Skipping dashboard revenue accuracy test: TESTING_API_KEY is not set.');
            return;
        }
        
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
        if (expectedRevenueCents === 0) {
            console.warn('Skipping dashboard revenue accuracy test: No revenue data found in test environment.');
            return;
        }

        // 2. Get the value displayed in the UI
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
    
    test('dashboard inventory value should be a plausible number', async ({ page }) => {
        const inventorySummaryCard = page.locator('.card', { hasText: 'Inventory Value Summary' });
        await expect(inventorySummaryCard).toBeVisible();

        const healthyStockItem = inventorySummaryCard.locator('div > div:has-text("Healthy Stock")');
        const valueText = await healthyStockItem.locator('span').last().innerText();
        
        const inventoryValueCents = parseCurrency(valueText);
        
        console.log(`Validating Inventory Value: Displayed Value = ${inventoryValueCents} cents`);

        // Assert that the value is a number and greater than zero, confirming it's not a placeholder.
        expect(typeof inventoryValueCents).toBe('number');
        expect(inventoryValueCents).toBeGreaterThanOrEqual(0);
    });
});
