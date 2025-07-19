
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Dead Stock Page', () => {

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/analytics/dead-stock');
  });

  test('should load and display dead stock analytics', async ({ page }) => {
    // Check for the main heading
    await expect(page.getByRole('heading', { name: 'Dead Stock Analysis' })).toBeVisible();

    // Check for the statistic cards
    await expect(page.getByRole('heading', { name: 'Dead Stock Value' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Dead Stock Units' })).toBeVisible();
    await expect(page.getByRole('heading', { name: 'Analysis Period' })).toBeVisible();

    // The page can either have a report table or an empty state. We will check for one of them.
    const reportTable = page.getByRole('table');
    const emptyStateMessage = page.getByText('No Dead Stock Found!');

    // Wait for either the table or the empty state message to be visible
    await Promise.race([
      expect(reportTable).toBeVisible(),
      expect(emptyStateMessage).toBeVisible(),
    ]);

    // Assert that one of them is indeed visible
    const isTableVisible = await reportTable.isVisible();
    const isMessageVisible = await emptyStateMessage.isVisible();
    expect(isTableVisible || isMessageVisible).toBeTruthy();
  });

});
