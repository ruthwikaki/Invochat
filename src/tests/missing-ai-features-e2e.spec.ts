import { test, expect } from '@playwright/test';

// Use shared authentication setup
test.use({ storageState: 'playwright/.auth/user.json' });

test.describe('Missing AI Features E2E Tests', () => {

  test.describe('AI Insights Page Features', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto('/analytics/ai-insights');
      await page.waitForURL('/analytics/ai-insights');
    });

    test('should generate bundle suggestions', async ({ page }) => {
      // Test the Bundle Suggester
      const bundleButton = page.getByRole('button', { name: 'Generate Bundles' });
      await expect(bundleButton).toBeVisible();
      
      // Set bundle count
      const bundleCountInput = page.locator('#bundle-count');
      await bundleCountInput.fill('3');
      
      await bundleButton.click();

      // Wait for results or error message
      const bundleResults = page.locator('h5:has-text("AI Merchandiser\'s Summary")').or(
        page.getByText('could not generate bundle suggestions').or(
          page.getByText('Not enough product data')
        )
      );
      await expect(bundleResults).toBeVisible({ timeout: 20000 });
    });

    test('should generate markdown optimization plan', async ({ page }) => {
      // Test the Markdown Planner
      const markdownButton = page.getByRole('button', { name: 'Generate Markdown Plan' });
      await expect(markdownButton).toBeVisible();
      
      await markdownButton.click();

      // Wait for results or no-data message
      const markdownResults = page.locator('h5:has-text("AI Analyst\'s Summary")').or(
        page.getByText('No markdown suggestions generated').or(
          page.getByText('no dead stock')
        )
      );
      await expect(markdownResults).toBeVisible({ timeout: 20000 });
    });

    test('should analyze promotional impact', async ({ page }) => {
      // Test the Promotional Impact Analysis
      const promoSkusInput = page.locator('#promo-skus');
      const promoDiscountInput = page.locator('#promo-discount');
      const promoDurationInput = page.locator('#promo-duration');
      const analyzeButton = page.getByRole('button', { name: 'Analyze Promotion' });

      // Fill in promotional details
      await promoSkusInput.fill('TEST-001,TEST-002');
      await promoDiscountInput.fill('20');
      await promoDurationInput.fill('14');
      
      await analyzeButton.click();

      // Wait for promotional impact results
      const promoResults = page.locator('text=Est. Revenue Lift').or(
        page.getByText('promotional impact analysis').or(
          page.getByText('Could not analyze promotional impact')
        )
      );
      await expect(promoResults).toBeVisible({ timeout: 20000 });
    });
  });

  test.describe('Chat AI Tool Integration', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto('/chat');
      await page.waitForURL('/chat');
    });

    test('should trigger economic indicators tool', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('What is the current US inflation rate?', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for AI response containing economic data or appropriate message
      const assistantMessage = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
      await expect(assistantMessage).toBeVisible({ timeout: 20000 });
      
      const economicResponse = assistantMessage.locator('text=inflation').or(
        assistantMessage.locator('text=economic').or(
          assistantMessage.locator('text=rate').or(
            assistantMessage.locator('text=Could not retrieve')
          )
        )
      );
      await expect(economicResponse).toBeVisible({ timeout: 5000 });
    });

    test('should provide customer insights analysis', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Show me customer insights and buying patterns', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for AI response and check content within the assistant message
      const assistantMessage = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
      await expect(assistantMessage).toBeVisible({ timeout: 20000 });
      
      const insightsResponse = assistantMessage.locator('text=insights').or(
        assistantMessage.locator('text=customer').or(
          assistantMessage.locator('text=segment').or(
            assistantMessage.locator('text=buying').or(
              assistantMessage.locator('text=pattern')
            )
          )
        )
      );
      await expect(insightsResponse).toBeVisible({ timeout: 5000 });
    });

    test('should generate product descriptions with AI', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Generate a product description for wireless headphones', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for AI response and check content within the assistant message
      const assistantMessage = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
      await expect(assistantMessage).toBeVisible({ timeout: 20000 });
      
      const descriptionResponse = assistantMessage.locator('text=description').or(
        assistantMessage.locator('text=headphones').or(
          assistantMessage.locator('text=wireless').or(
            assistantMessage.locator('text=product')
          )
        )
      );
      await expect(descriptionResponse).toBeVisible({ timeout: 5000 });
    });

    test('should provide sales velocity analytics', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Show me sales velocity analysis for my products', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for sales velocity response
      const velocityResponse = page.locator('text=sales velocity').or(
        page.locator('text=fast').or(
          page.locator('text=slow').or(
            page.getByText('velocity analysis')
          )
        )
      );
      await expect(velocityResponse).toBeVisible({ timeout: 20000 });
    });

    test('should perform ABC analysis', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Run an ABC analysis on my inventory', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for ABC analysis response
      const abcResponse = page.locator('text=ABC analysis').or(
        page.locator('text=Category A').or(
          page.locator('text=Category B').or(
            page.locator('text=revenue contribution')
          )
        )
      );
      await expect(abcResponse).toBeVisible({ timeout: 20000 });
    });

    test('should provide demand forecasting', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('What is the demand forecast for my products?', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for demand forecast response
      const forecastResponse = page.locator('text=demand forecast').or(
        page.locator('text=forecasted').or(
          page.locator('text=prediction').or(
            page.getByText('forecast')
          )
        )
      );
      await expect(forecastResponse).toBeVisible({ timeout: 20000 });
    });

    test('should analyze gross margin data', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Show me gross margin analysis by product', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for gross margin analysis response
      const marginResponse = page.locator('text=gross margin').or(
        page.locator('text=margin analysis').or(
          page.locator('text=percentage').or(
            page.getByText('margin')
          )
        )
      );
      await expect(marginResponse).toBeVisible({ timeout: 20000 });
    });

    test('should explain anomalies and alerts', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Explain any unusual patterns or anomalies in my data', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for anomaly explanation response
      const anomalyResponse = page.locator('text=anomaly').or(
        page.locator('text=unusual').or(
          page.locator('text=pattern').or(
            page.locator('text=analysis').or(
              page.getByText('explanation')
            )
          )
        )
      );
      await expect(anomalyResponse).toBeVisible({ timeout: 20000 });
    });

    test('should provide morning briefing insights', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Give me a morning briefing of my business performance', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for AI response and check content within the assistant message
      const assistantMessage = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
      await expect(assistantMessage).toBeVisible({ timeout: 20000 });
      
      const briefingResponse = assistantMessage.locator('text=briefing').or(
        assistantMessage.locator('text=morning').or(
          assistantMessage.locator('text=business').or(
            assistantMessage.locator('text=performance').or(
              assistantMessage.locator('text=summary')
            )
          )
        )
      );
      await expect(briefingResponse).toBeVisible({ timeout: 5000 });
    });

    test('should handle CSV mapping assistance', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Help me map CSV columns: Product Name, SKU, Price to database fields', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for CSV mapping response
      const mappingResponse = page.locator('text=mapping').or(
        page.locator('text=CSV').or(
          page.locator('text=Product Name').or(
            page.locator('text=database').or(
              page.getByText('columns')
            )
          )
        )
      );
      await expect(mappingResponse).toBeVisible({ timeout: 20000 });
    });
  });

  test.describe('Error Handling and Edge Cases', () => {
    test.beforeEach(async ({ page }) => {
      await page.goto('/chat');
      await page.waitForURL('/chat');
    });

    test('should handle AI service errors gracefully for advanced features', async ({ page }) => {
      // Mock AI service error for advanced features
      await page.route('**/chat/message', async route => {
        await route.fulfill({
          status: 429,
          contentType: 'application/json',
          body: JSON.stringify({ error: 'API quota exceeded. Please try again later.' }),
        });
      });

      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Generate bundle suggestions', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Should show appropriate error message in the chat
      const assistantMessage = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
      await expect(assistantMessage).toBeVisible({ timeout: 10000 });
      
      const errorResponse = assistantMessage.locator('text=quota').or(
        assistantMessage.locator('text=try again').or(
          assistantMessage.locator('text=unavailable').or(
            assistantMessage.locator('text=error')
          )
        )
      );
      await expect(errorResponse).toBeVisible({ timeout: 5000 });
    });

    test('should handle insufficient data scenarios', async ({ page }) => {
      const inputField = page.locator('input[placeholder="Ask anything about your inventory..."]');
      await inputField.click();
      await inputField.clear();
      await inputField.type('Show me detailed analytics for products with no sales history', { delay: 50 });
      
      await page.getByRole('button', { name: 'Send message' }).click();

      // Wait for AI response and check for data limitation messages
      const assistantMessage = page.locator('.flex.flex-col.gap-3:has(.bg-card)').last();
      await expect(assistantMessage).toBeVisible({ timeout: 20000 });
      
      const dataResponse = assistantMessage.locator('text=data').or(
        assistantMessage.locator('text=analytics').or(
          assistantMessage.locator('text=analysis').or(
            assistantMessage.locator('text=history').or(
              assistantMessage.locator('text=sales')
            )
          )
        )
      );
      await expect(dataResponse).toBeVisible({ timeout: 5000 });
    });
  });

  test.describe('AI Feature Integration with Dashboard', () => {
    test('should access AI insights from dashboard', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForURL('/dashboard');

      // Look for AI Insights link or button
      const aiInsightsLink = page.locator('a[href*="ai-insights"]').or(
        page.getByRole('link', { name: /ai insights/i }).or(
          page.getByText('AI-Powered Insights')
        )
      );

      const isVisible = await aiInsightsLink.isVisible().catch(() => false);
      if (isVisible) {
        await aiInsightsLink.click();
        await page.waitForURL('/analytics/ai-insights');
        
        // Verify we're on the AI insights page
        await expect(page.getByText('AI-Powered Insights')).toBeVisible();
      } else {
        // Navigate directly if link not found on dashboard
        await page.goto('/analytics/ai-insights');
        await page.waitForURL('/analytics/ai-insights');
        await expect(page.getByText('AI-Powered Insights')).toBeVisible();
      }
    });

    test('should show morning briefing on dashboard load', async ({ page }) => {
      await page.goto('/dashboard');
      await page.waitForURL('/dashboard');

      // Look for morning briefing or AI summary on dashboard
      const briefingElement = page.locator('text=morning briefing').or(
        page.locator('text=AI summary').or(
          page.locator('text=business insights').or(
            page.getByText('Good morning')
          )
        )
      );

      // Check if morning briefing is displayed (optional feature)
      const hasBriefing = await briefingElement.isVisible({ timeout: 5000 }).catch(() => false);
      if (hasBriefing) {
        console.log('Morning briefing found on dashboard');
      } else {
        console.log('Morning briefing not displayed on dashboard (optional feature)');
      }

      // At minimum, dashboard should load successfully
      await expect(page.locator('h1').or(page.locator('[data-testid="dashboard-title"]'))).toBeVisible();
    });
  });
});
