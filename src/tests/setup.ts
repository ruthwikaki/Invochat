import { vi } from 'vitest';

// Mock the logger to prevent console output during tests
vi.mock('@/lib/logger', () => ({
  logger: {
    debug: vi.fn(),
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

// Mock the Supabase client to avoid actual DB calls in unit tests
vi.mock('@/lib/supabase/admin', () => ({
  getServiceRoleClient: vi.fn(() => ({
    from: vi.fn(() => ({
      select: vi.fn().mockReturnThis(),
      insert: vi.fn().mockReturnThis(),
      update: vi.fn().mockReturnThis(),
      delete: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      in: vi.fn().mockReturnThis(),
      or: vi.fn().mockReturnThis(),
      not: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({ data: {}, error: null }),
    })),
    rpc: vi.fn().mockResolvedValue({ data: {}, error: null }),
    auth: {
      admin: {
        createUser: vi.fn(),
        deleteUser: vi.fn(),
      }
    }
  })),
  createServerClient: vi.fn(),
}));

vi.mock('@/lib/auth-helpers', async (importOriginal) => {
    const actual = await importOriginal();
    return {
        ...actual,
        getAuthContext: vi.fn().mockResolvedValue({
            userId: 'test-user-id',
            companyId: 'test-company-id',
        }),
    }
});
