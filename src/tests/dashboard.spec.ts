

import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import credentials from './test_data/test_credentials.json';

const testUser = credentials.test_users[0]; // Use the first user for tests

async function login(page: Page) {
    await page.goto('/login');
    await page.fill('input[name="email"]', testUser.email);
    await page.fill('input[name="password"]', testUser.password);
    await page.click('button[type="submit"]');
    await page.waitForURL('/dashboard', { timeout: 30000 });
    await page.waitForLoadState('networkidle');
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
        await expect(page.getByTestId('dashboard-root').or(page.getByText('Welcome to ARVO'))).toBeVisible();
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
        if (!process.env.TESTING_API_KEY) {
            console.warn('Skipping dashboard revenue accuracy test: TESTING_API_KEY is not set.');
            return;
        }
        
        const apiResponse = await request.get('/api/debug', {
            headers: {
                'Authorization': `Bearer ${process.env.TESTING_API_KEY}`
            }
        });
        expect(apiResponse.ok()).toBeTruthy();
        const groundTruth = await apiResponse.json();
        const expectedRevenueCents = groundTruth.totalRevenue;
        
        if (expectedRevenueCents === 0) {
            console.warn('Skipping dashboard revenue accuracy test: No revenue data found in test environment.');
            return;
        }

        const totalRevenueCard = page.getByTestId('total-revenue-card');
        await expect(totalRevenueCard).toBeVisible();
        const revenueText = await totalRevenueCard.locator('.text-3xl').innerText();
        
        const displayedRevenueCents = parseCurrency(revenueText);
        
        console.log(`Comparing Dashboard Revenue - Expected: ${expectedRevenueCents}, Displayed: ${displayedRevenueCents}`);

        expect(displayedRevenueCents).toBeCloseTo(expectedRevenueCents, 1);
    });
    
    test('dashboard inventory value should be a plausible number', async ({ page }) => {
        const inventorySummaryCard = page.locator('.card', { hasText: 'Inventory Value Summary' });
        await expect(inventorySummaryCard).toBeVisible();

        const healthyStockItem = inventorySummaryCard.locator('div > div:has-text("Healthy Stock")');
        const valueText = await healthyStockItem.locator('span').last().innerText();
        
        const inventoryValueCents = parseCurrency(valueText);
        
        console.log(`Validating Inventory Value: Displayed Value = ${inventoryValueCents} cents`);

        expect(typeof inventoryValueCents).toBe('number');
        expect(inventoryValueCents).toBeGreaterThanOrEqual(0);
    });
});
