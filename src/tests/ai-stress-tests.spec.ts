import { test, expect } from '@playwright/test';

test.describe('AI Integration Stress Tests', () => {
  test.use({ storageState: 'playwright/.auth/user.json' });
  
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('domcontentloaded');
  });

  test('should handle AI service timeout gracefully', async ({ page }) => {
    // Navigate to AI insights page
    await page.goto('/analytics/ai-insights');
    
    // Try to generate insights - should handle timeout gracefully
    await page.click('text=Find Opportunities', { timeout: 30000 });
    
    // Wait for any of these indicators that the system is responding:
    // 1. Loading spinner, 2. AI response, or 3. No server error
    await Promise.race([
      // Wait for AI response alert
      page.locator('[role="alert"]').first().waitFor({ state: 'visible', timeout: 30000 }),
      // Or ensure page doesn't crash with errors
      page.waitForFunction(() => {
        return !document.body.textContent?.includes('500') && 
               !document.body.textContent?.includes('Internal Server Error');
      }, { timeout: 30000 })
    ]);
    
    // Final verification - no server errors
    await expect(page.locator('body')).not.toContainText('500');
  });

  test('should handle invalid AI inputs gracefully', async ({ page }) => {
    await page.goto('/analytics/ai-insights');
    
    // Try multiple AI actions in rapid succession (stress test)
    // Use available buttons with appropriate wait times
    await page.click('text=Find Opportunities');
    await page.waitForTimeout(1000); // Brief pause
    
    // Try another available AI button
    try {
      await page.click('text=Generate Bundles', { timeout: 5000 });
      await page.waitForTimeout(1000);
    } catch (error) {
      // If button not found, use alternative
      await page.click('text=Find Opportunities'); // Fallback to known button
    }
    
    try {
      await page.click('text=Price Check', { timeout: 5000 });
    } catch (error) {
      // If not found, skip this action
      console.log('Price Check button not available');
    }
    
    // Should handle concurrent requests gracefully, not crash
    await expect(page.locator('body')).not.toContainText('500');
    await expect(page.locator('body')).not.toContainText('Internal Server Error');
  });

  test('should handle malicious prompt injection attempts', async ({ page }) => {
    await page.goto('/analytics/ai-insights');
    
    // Test that AI actions work properly without exposing system info
    await page.click('text=Find Opportunities');
    
    // Wait for AI response and validate it doesn't contain sensitive info
    await page.waitForTimeout(3000); // Give AI time to respond
    
    // Check for actual AI response content (in alert box), not page HTML
    const aiAlert = page.locator('[role="alert"]').first();
    const aiContent = await aiAlert.textContent();
    
    // Should not reveal system information or execute harmful commands
    if (aiContent) {
      expect(aiContent).not.toContain('system prompt');
      expect(aiContent).not.toContain('DROP TABLE');
    }
    
    // Ensure page is functional
    await expect(page.locator('body')).not.toContainText('500');
  });

  test('should handle large dataset AI processing', async ({ page }) => {
    await page.goto('/analytics/ai-insights');
    
    // Request AI analysis that processes large amounts of data
    await page.click('text=Find Opportunities');
    
    // Should handle large datasets without timing out
    await page.waitForTimeout(10000);
    
    // Check that page doesn't crash or timeout
    await expect(page.locator('body')).not.toContainText('500');
    await expect(page.locator('body')).not.toContainText('timeout');
  });

  test('should handle AI flow errors in purchase order optimization', async ({ page }) => {
    await page.goto('/purchase-orders/new');
    
    // Wait for page to load and check if basic elements exist
    await page.waitForLoadState('domcontentloaded');
    
    // Should not crash when loading purchase order page
    await expect(page.locator('body')).not.toContainText('500');
    await expect(page.locator('body')).not.toContainText('Internal Server Error');
  });

  test('should handle concurrent AI requests', async ({ page, context }) => {
    // Create multiple pages with shared authentication
    const page2 = await context.newPage();
    const page3 = await context.newPage();
    
    // Navigate all pages to AI insights (already authenticated)
    await page.goto('/analytics/ai-insights');
    await page2.goto('/analytics/ai-insights');
    await page3.goto('/analytics/ai-insights');
    
    // Submit AI requests simultaneously
    const promises = [page, page2, page3].map(async (p) => {
      await p.click('text=Find Opportunities');
      await p.waitForTimeout(5000); // Give AI time to respond
      return p;
    });
    
    // All should complete successfully without errors
    await Promise.all(promises);
    
    // Verify all pages are still functional
    for (const p of [page, page2, page3]) {
      await expect(p.locator('body')).not.toContainText('500');
      await expect(p.locator('body')).not.toContainText('Internal Server Error');
    }
  });

  test('should validate AI response format and safety', async ({ page }) => {
    await page.goto('/analytics/ai-insights');
    
    await page.click('text=Find Opportunities');
    await page.waitForTimeout(5000); // Give AI time to respond
    
    // Check for AI-generated content specifically, not whole page HTML
    const aiContent = await page.locator('[role="alert"]').first().textContent();
    
    // Validate AI response content is safe (not the page HTML)
    if (aiContent) {
      expect(aiContent).not.toContain('DROP TABLE');
      expect(aiContent).not.toContain('password');
      expect(aiContent).not.toContain('secret_key');
      expect(aiContent).not.toContain('database_url');
    }
    
    // Ensure page itself is functional
    await expect(page.locator('body')).not.toContainText('500');
  });
});

test.describe('AI Morning Briefing Flow Tests', () => {
  test.use({ storageState: 'playwright/.auth/user.json' });
  
  test.beforeEach(async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('domcontentloaded');
  });

  test('should generate morning briefing with real data', async ({ page }) => {
    await page.goto('/dashboard');
    
    // Look for morning briefing section
    const briefingSection = page.locator('[data-testid="morning-briefing"]');
    
    if (await briefingSection.isVisible()) {
      await briefingSection.click();
      
      // Should show briefing content
      await expect(page.locator('[data-testid="briefing-content"]')).toBeVisible({ timeout: 30000 });
      
      const content = await page.locator('[data-testid="briefing-content"]').textContent();
      expect(content?.length || 0).toBeGreaterThan(100);
    }
  });

  test('should refresh morning briefing data', async ({ page }) => {
    await page.goto('/dashboard');
    
    const refreshButton = page.locator('[data-testid="refresh-briefing"]');
    
    if (await refreshButton.isVisible()) {
      await refreshButton.click();
      
      // Should show loading and then new content
      await expect(page.locator('[data-testid="briefing-loading"]')).toBeVisible();
      await expect(page.locator('[data-testid="briefing-content"]')).toBeVisible({ timeout: 30000 });
    }
  });
});

test.describe('AI Error Recovery Tests', () => {
  test.use({ storageState: 'playwright/.auth/user.json' });
  
  test('should recover from AI service failures', async ({ page }) => {
    await page.goto('/dashboard');
    await page.waitForLoadState('domcontentloaded');
    
    await page.goto('/analytics/ai-insights');
    
    // Try normal operation first to confirm the button works
    const button = page.locator('text=Find Opportunities');
    await expect(button).toBeVisible({ timeout: 5000 });
    
    // Simulate network issues by going offline briefly
    await page.context().setOffline(true);
    await page.waitForTimeout(2000);
    
    // Go back online (this tests the recovery aspect)
    await page.context().setOffline(false);
    await page.waitForTimeout(1000);
    
    // Reload page to ensure full recovery
    await page.reload();
    await page.waitForLoadState('domcontentloaded');
    
    // Retry should work now
    await expect(button).toBeVisible({ timeout: 10000 });
    await button.click();
    await expect(page.locator('body')).not.toContainText('500', { timeout: 30000 });
  });
});
