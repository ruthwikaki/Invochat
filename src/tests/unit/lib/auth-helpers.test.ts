
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getAuthContext, getCurrentUser } from '@/lib/auth-helpers';
import { createServerClient, getServiceRoleClient } from '@/lib/supabase/admin';
import { retry } from '@/lib/async-utils';

// Mock dependencies
vi.mock('@/lib/supabase/admin');
vi.mock('@/lib/async-utils');

const mockUser = {
  id: 'user-123',
  email: 'test@example.com',
  app_metadata: {
    company_id: 'company-456',
  },
};

describe('Auth Helpers', () => {
  let supabaseMock: any;
  let serviceSupabaseMock: any;

  beforeEach(() => {
    supabaseMock = {
      auth: {
        getUser: vi.fn(),
      },
    };
    serviceSupabaseMock = {
        from: vi.fn().mockReturnThis(),
        select: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        single: vi.fn().mockResolvedValue({ data: { company_id: 'company-db-fallback' }, error: null }),
    };
    (createServerClient as any).mockReturnValue(supabaseMock);
    (getServiceRoleClient as any).mockReturnValue(serviceSupabaseMock);
    (retry as any).mockImplementation((fn: () => any) => fn());
    vi.clearAllMocks();
  });

  describe('getCurrentUser', () => {
    it('should return the user when authenticated', async () => {
      supabaseMock.auth.getUser.mockResolvedValue({ data: { user: mockUser }, error: null });
      const user = await getCurrentUser();
      expect(user).toEqual(mockUser);
    });

    it('should return null when not authenticated', async () => {
      supabaseMock.auth.getUser.mockResolvedValue({ data: { user: null }, error: null });
      const user = await getCurrentUser();
      expect(user).toBeNull();
    });

    it('should return null on error', async () => {
      supabaseMock.auth.getUser.mockResolvedValue({ data: { user: null }, error: new Error('DB connection failed') });
      const user = await getCurrentUser();
      expect(user).toBeNull();
    });
  });

  describe('getAuthContext', () => {
    it('should return user and company ID when authenticated', async () => {
        supabaseMock.auth.getUser.mockResolvedValue({ data: { user: mockUser }, error: null });
        const context = await getAuthContext();
        expect(context).toEqual({ userId: 'user-123', companyId: 'company-456' });
    });

    it('should throw error if user is not found', async () => {
        supabaseMock.auth.getUser.mockResolvedValue({ data: { user: null }, error: null });
        await expect(getAuthContext()).rejects.toThrow('Authentication required: No user session found.');
    });

     it('should throw error if company ID is missing from JWT and DB fallback fails', async () => {
        const userWithoutCompany = { ...mockUser, app_metadata: {} };
        supabaseMock.auth.getUser.mockResolvedValue({ data: { user: userWithoutCompany }, error: null });
        // Mock the db call to also fail
        (retry as any).mockRejectedValue(new Error("Failed after retries"));
        await expect(getAuthContext()).rejects.toThrow('Authorization failed: User is not associated with a company.');
    });
  });
});
