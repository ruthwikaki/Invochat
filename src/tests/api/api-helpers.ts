import { request, APIRequestContext } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';

// NOTE: This helper uses environment variables and should only be run in a secure test environment.
// It uses the service role key to directly sign in a user for testing purposes.

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL || 'test@example.com';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'password';

let accessToken: string | null = null;

/**
 * Gets an authenticated APIRequestContext for making requests as a test user.
 * It will sign in the user once and reuse the token for subsequent requests.
 * @param playwrightRequest The `request` object from a Playwright test.
 * @returns An authenticated APIRequestContext.
 */
export async function getAuthedRequest(playwrightRequest?: APIRequestContext): Promise<APIRequestContext> {
  if (!accessToken) {
    const supabase = getServiceRoleClient();
    
    // Check if the user exists, if not, create it for the test run.
    const { data: { users }, error: listError } = await supabase.auth.admin.listUsers();
    if (listError) throw new Error('Could not list users to find test user.');
    
    const testUser = users.find(u => u.email === TEST_USER_EMAIL);
    if (!testUser) {
        const { error: createError } = await supabase.auth.admin.createUser({
            email: TEST_USER_EMAIL,
            password: TEST_USER_PASSWORD,
            email_confirm: true, // Auto-confirm user for tests
        });
        if(createError) throw new Error(`Failed to create test user: ${createError.message}`);
    }

    const response = await request.newContext().post(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      data: {
        email: TEST_USER_EMAIL,
        password: TEST_USER_PASSWORD,
      },
    });
    
    if (!response.ok()) {
        throw new Error(`Failed to authenticate test user: ${await response.text()}`);
    }
    const authData = await response.json();
    accessToken = authData.access_token;
  }
  
  const client = playwrightRequest || await request.newContext();

  // Return a new context with the Authorization header set
  return new Proxy(client, {
    get(target, prop, receiver) {
        const originalMethod = (target as any)[prop];
        if (typeof originalMethod === 'function' && ['get', 'post', 'put', 'delete', 'patch', 'head'].includes(String(prop))) {
            return (url: string, options: any = {}) => {
                const headers = { ...options.headers, Authorization: `Bearer ${accessToken}` };
                return originalMethod.call(target, url, { ...options, headers });
            };
        }
        return Reflect.get(target, prop, receiver);
    }
  }) as APIRequestContext;
}
