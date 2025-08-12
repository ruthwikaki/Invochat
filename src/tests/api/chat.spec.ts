
import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';
import * as crypto from 'crypto';

test.describe('Chat API', () => {

  test('POST /api/chat/message should process a message and return an AI response', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.post('/api/chat/message', {
      data: {
        content: "What is my most profitable item?",
        conversationId: crypto.randomUUID(),
      }
    });

    expect(response.ok()).toBeTruthy();
    const data = await response.json();
    expect(data).toHaveProperty('newMessage');
    expect(data).toHaveProperty('conversationId');
    expect(data.newMessage.role).toBe('assistant');
    expect(data.newMessage.content).toBeDefined();
  });

});
