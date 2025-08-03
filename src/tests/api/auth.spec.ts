
import { test, expect } from '@playwright/test';
import { getAuthedRequest } from './api-helpers';
import { createServerClient } from '@/lib/supabase/admin';

test.describe('Authentication API', () => {

  test('GET /api/auth/user should not exist', async ({ request }) => {
    // This endpoint should not exist as user data should be retrieved through the session on the server
    const response = await request.get('/api/auth/user');
    expect(response.status()).toBe(404);
  });
  
});
