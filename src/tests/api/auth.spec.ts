import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';

test.describe('Authentication API', () => {

  test('GET /api/auth/user should return user data for authenticated requests', async ({ request }) => {
    const authedRequest = await getAuthedRequest(request);
    const response = await authedRequest.get('/api/auth/user');

    expect(response.ok()).toBeTruthy();
    const { user } = await response.json();
    expect(user).toHaveProperty('id');
    expect(user.email).toBe(process.env.TEST_USER_EMAIL || 'test@example.com');
  });

  test('GET /api/auth/user should return 401 for unauthenticated requests', async ({ request }) => {
    const response = await request.get('/api/auth/user');
    expect(response.status()).toBe(401);
  });
  
});
