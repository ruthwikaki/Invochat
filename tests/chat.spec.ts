
import { test, expect } from '@playwright/test';
import { login } from './utils';

test.describe('AI Chat Interface', () => {

  test.beforeEach(async ({ page, context }) => {
    await login(page, context);
    await page.goto('/chat');
  });

  test('should send a message and receive an AI response', async ({ page }) => {
    const userMessage = 'Show me my dead stock';
    
    // Mock the network call to the server action
    await page.route('**/chat?id=', async (route) => {
      const request = route.request();
      if (request.method() === 'POST' && request.url().includes('/chat?id=')) {
        // This is our server action call, let's mock its response
        const mockResponse = {
          newMessage: {
            id: 'ai_12345',
            conversation_id: 'mock_convo_123',
            company_id: 'mock_company_123',
            role: 'assistant',
            content: "Here is your dead stock report. I found 2 items that haven't sold recently.",
            visualization: { type: 'none' },
            created_at: new Date().toISOString(),
          },
          conversationId: 'mock_convo_123',
        };

        return await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify(mockResponse),
        });
      }
      // For all other requests, continue as normal
      return await route.continue();
    });

    // Find the chat input and send a message
    const chatInput = page.getByPlaceholder('Ask anything about your inventory...');
    await chatInput.fill(userMessage);
    await page.getByRole('button', { name: 'Send' }).click();

    // The user's message should appear on the screen immediately
    await expect(page.locator('body')).toContainText(userMessage);

    // A loading indicator should appear
    const loadingIndicator = page.locator('//div[contains(., "...")]');
    await expect(loadingIndicator).toBeVisible();
    
    // The mocked AI response should appear
    const aiResponse = page.locator("text=Here is your dead stock report.");
    await expect(aiResponse).toBeVisible({ timeout: 10000 }); // Wait up to 10s for the response

    // The loading indicator should disappear
    await expect(loadingIndicator).not.toBeVisible();
  });

  test('should allow using a quick action button', async ({ page }) => {
    // Find a quick action button and click it
    const quickActionButton = page.getByRole('button', { name: 'Show me my dead stock report' });
    await expect(quickActionButton).toBeVisible();
    await quickActionButton.click();

    // The chat input should now be empty, as the message was sent
    const chatInput = page.getByPlaceholder('Ask anything about your inventory...');
    await expect(chatInput).toHaveValue('');

    // The quick action text should appear as a user message
    await expect(page.locator('body')).toContainText('Show me my dead stock report');
    
    // A loading indicator should be visible
    const loadingIndicator = page.locator('//div[contains(., "...")]');
    await expect(loadingIndicator).toBeVisible();
  });
});
