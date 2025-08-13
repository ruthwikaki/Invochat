
import { test, expect } from '@playwright/test';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { getAuthedRequest } from '../api/api-helpers';

// This test checks for Insecure Direct Object Reference (IDOR) vulnerabilities
// by ensuring one user cannot access another user's data.

test.describe('Data Security & Multi-Tenancy', () => {
    let company1Id: string;
    let company2Id: string;
    let supplierFromCompany1Id: string;

    test.beforeAll(async () => {
        const supabase = getServiceRoleClient();
        // Create two separate companies and a supplier in the first one
        const { data: comp1 } = await supabase.from('companies').insert({ name: 'Security Test Co 1', owner_id: null }).select().single();
        const { data: comp2 } = await supabase.from('companies').insert({ name: 'Security Test Co 2', owner_id: null }).select().single();
        if(!comp1 || !comp2) throw new Error('Failed to create test companies');
        company1Id = comp1.id;
        company2Id = comp2.id;
        
        const { data: supplier } = await supabase.from('suppliers').insert({ name: 'Company 1 Supplier', company_id: company1Id }).select().single();
        if(!supplier) throw new Error('Failed to create test supplier');
        supplierFromCompany1Id = supplier.id;
    });

    test('should prevent a user from one company from accessing data from another', async () => {
        // Authenticate as a user from Company 2. `getAuthedRequest` is configured
        // to use a test user that we can associate with Company 2 for this test.
        const supabase = getServiceRoleClient();
        const {data: {users}} = await supabase.auth.admin.listUsers();
        const testUser = users.find(u => u.email === (process.env.TEST_USER_EMAIL || 'test@example.com'));
        if (!testUser) throw new Error('Test user not found');

        // Temporarily assign the test user to Company 2
        await supabase.from('company_users').upsert({ user_id: testUser.id, company_id: company2Id, role: 'Owner' }, { onConflict: 'user_id' });

        const authedRequest = await getAuthedRequest();
        
        // As a user from Company 2, try to fetch the supplier from Company 1
        const response = await authedRequest.get(`/api/suppliers/${supplierFromCompany1Id}`);

        // The API should return a 404 Not Found, because from Company 2's perspective,
        // that supplier does not exist. A 403 Forbidden would also be acceptable.
        // A 200 OK would indicate a critical RLS failure.
        expect(response.status()).toBe(404);
    });

    test.afterAll(async () => {
        const supabase = getServiceRoleClient();
        await supabase.from('suppliers').delete().eq('id', supplierFromCompany1Id);
        await supabase.from('companies').delete().in('id', [company1Id, company2Id]);
    });
});

