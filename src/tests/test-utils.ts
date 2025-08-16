import { Page } from '@playwright/test';

export const TEST_USERS = {
  admin: {
    email: 'admin_stylehub@test.com',
    password: 'StyleHub2024!'
  },
  member: {
    email: 'member_stylehub@test.com', 
    password: 'StyleHub2024!'
  },
  owner: {
    email: 'owner_stylehub@test.com',
    password: 'StyleHub2024!'
  }
};

export async function login(page: Page, user?: { email: string, password: string }, options?: { skipIfLoggedIn?: boolean }) {
    const loginUser = user || TEST_USERS.admin;
    
    // If skipIfLoggedIn is true and we're already on dashboard, skip login
    if (options?.skipIfLoggedIn) {
        try {
            await page.goto('/dashboard', { waitUntil: 'networkidle', timeout: 10000 });
            if (page.url().includes('/dashboard')) {
                console.log('✅ Already logged in, skipping login process');
                return;
            }
        } catch {
            // Not logged in, continue with login process
        }
    }
    
    console.log(`🔐 Logging in as ${loginUser.email}...`);
    
    // Navigate to login and wait for page to be ready
    await page.goto('/login', { waitUntil: 'networkidle' });
    
    // Wait for login form to be visible and interactable
    await page.waitForSelector('input[name="email"]', { state: 'visible' });
    await page.waitForSelector('input[name="password"]', { state: 'visible' });
    await page.waitForSelector('button[type="submit"]', { state: 'visible' });
    
    // Fill form fields
    await page.fill('input[name="email"]', loginUser.email);
    await page.fill('input[name="password"]', loginUser.password);
    
    // Submit form and wait for navigation
    const navigationPromise = page.waitForURL('/dashboard', { timeout: 45000 });
    await page.click('button[type="submit"]');
    
    try {
        await navigationPromise;
        console.log(`✅ Successfully logged in as ${loginUser.email}`);
    } catch (error) {
        console.error(`❌ Login failed for ${loginUser.email}:`, error);
        // Take a screenshot for debugging
        await page.screenshot({ path: `login-failure-${Date.now()}.png`, fullPage: true });
        throw error;
    }
}

// For tests that need to switch to a different user without using shared auth
export async function switchUser(page: Page, user: { email: string; password: string }) {
    console.log(`🔄 Switching to user: ${user.email}`);
    
    // Logout first by clearing auth state
    await page.context().clearCookies();
    await page.evaluate(() => {
        localStorage.clear();
        sessionStorage.clear();
    });
    
    // Login as new user
    await login(page, user);
}

export async function waitForPageLoad(page: Page, timeout = 30000) {
    // Wait for the page to be fully loaded
    await page.waitForLoadState('networkidle', { timeout });
    
    // Wait for any loading spinners to disappear
    try {
        await page.waitForSelector('[data-testid="loading"]', { state: 'hidden', timeout: 5000 });
    } catch {
        // Loading indicator may not exist, that's fine
    }
}
