
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('Main Navigation', () => {

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/dashboard');
  });

  test('should display the Settings navigation link for an admin user', async ({ page }) => {
    // Find the sidebar menu
    const sidebar = page.locator('[data-sidebar="sidebar"]');
    
    // Find the "Settings" menu button within the sidebar
    // This button might be collapsed into a trigger or be fully visible
    const settingsButton = sidebar.getByRole('button', { name: 'Settings' });

    // The button itself should always be visible to an admin/owner
    await expect(settingsButton).toBeVisible();

    // Click the button to ensure the submenu (or link) is accessible
    await settingsButton.click();
    
    // Now check for the actual link to the profile settings
    const profileLink = sidebar.getByRole('link', { name: 'Profile' });
    await expect(profileLink).toBeVisible();
    await expect(profileLink).toHaveAttribute('href', '/settings/profile');
  });

});
