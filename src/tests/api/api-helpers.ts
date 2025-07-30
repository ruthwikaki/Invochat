
import { request, APIRequestContext } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';

// NOTE: This helper uses environment variables and should only be run in a secure test environment.
// It uses the service role key to directly sign in a user for testing purposes.

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const TEST_USER_EMAIL = process.env.TEST_USER_EMAIL || 'test@example.com';
const TEST_USER_PASSWORD = process.env.TEST_USER_PASSWORD || 'password';

let accessToken: string | null = null;

/**
 * Creates a new user for testing purposes and assigns them to a specific company.
 * @param email The email for the new test user.
 * @param password The password for the new test user.
 * @param companyId The ID of the company to assign the user to.
 * @param role The role to assign to the user within the company.
 * @returns An object containing the new user's ID, email, and an access token for API requests.
 */
export async function createTestUser(
  { email, password, companyId, role = 'Owner' }: 
  { email: string; password; string; companyId: string; role?: 'Owner' | 'Admin' | 'Member' }
) {
    const supabase = getServiceRoleClient();
    
    // 1. Create the user in Supabase Auth
    const { data: { user }, error: createError } = await supabase.auth.admin.createUser({
        email: email,
        password: password,
        email_confirm: true, // Auto-confirm user for tests
    });

    if (createError) {
        throw new Error(`Failed to create test user ${email}: ${createError.message}`);
    }
    if (!user) {
         throw new Error('User was not returned after creation.');
    }

    // 2. Link the user to the specified company
    const { error: linkError } = await supabase.from('company_users').insert({
        user_id: user.id,
        company_id: companyId,
        role: role
    });
    
    if (linkError) {
        // Cleanup the created user if linking fails
        await supabase.auth.admin.deleteUser(user.id);
        throw new Error(`Failed to link user ${email} to company ${companyId}: ${linkError.message}`);
    }
    
    // 3. Get an access token for the new user
    const { data: tokenData, error: tokenError } = await supabase.auth.signInWithPassword({ email, password });
    if(tokenError || !tokenData.session) {
        throw new Error(`Failed to sign in as new test user ${email}: ${tokenError?.message}`);
    }

    return {
        userId: user.id,
        email: user.email,
        accessToken: tokenData.session.access_token,
    };
}


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
