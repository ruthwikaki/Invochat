import { describe, it, expect, vi, beforeEach } from 'vitest';
import { getAuthContext, getCurrentUser, getCurrentCompanyId } from '@/lib/auth-helpers';
import { createServerClient } from '@/lib/supabase/admin';

// Mock the createServerClient function
vi.mock('@/lib/supabase/admin', () => ({
  createServerClient: vi.fn(),
}));

const mockUser = {
  id: 'user-123',
  email: 'test@example.com',
  app_metadata: {
    company_id: 'company-456',
  },
};

describe('Auth Helpers', () => {
  let supabaseMock: any;

  beforeEach(() => {
    supabaseMock = {
      auth: {
        getUser: vi.fn(),
      },
    };
    (createServerClient as vi.Mock).mockReturnValue(supabaseMock);
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

  describe('getCurrentCompanyId', () => {
    it('should return company ID for an authenticated user', async () => {
        supabaseMock.auth.getUser.mockResolvedValue({ data: { user: mockUser }, error: null });
        const companyId = await getCurrentCompanyId();
        expect(companyId).toBe('company-456');
    });

    it('should return null if user has no company ID', async () => {
        const userWithoutCompany = { ...mockUser, app_metadata: {} };
        supabaseMock.auth.getUser.mockResolvedValue({ data: { user: userWithoutCompany }, error: null });
        const companyId = await getCurrentCompanyId();
        expect(companyId).toBeNull();
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

     it('should throw error if company ID is missing', async () => {
        const userWithoutCompany = { ...mockUser, app_metadata: {} };
        supabaseMock.auth.getUser.mockResolvedValue({ data: { user: userWithoutCompany }, error: null });
        await expect(getAuthContext()).rejects.toThrow('Authorization failed: User is not associated with a company.');
    });
  });
});
