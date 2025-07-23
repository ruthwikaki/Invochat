import '@testing-library/jest-dom/vitest';
import { vi } from 'vitest';
import { JSDOM } from 'jsdom';

// Setup JSDOM
const dom = new JSDOM('<!doctype html><html><body></body></html>', {
    url: 'http://localhost/'
});
global.window = dom.window as unknown as Window & typeof globalThis;
global.document = dom.window.document;
global.navigator = dom.window.navigator;
global.requestAnimationFrame = cb => setTimeout(cb, 0);
global.cancelAnimationFrame = id => clearTimeout(id);


// Mock Next.js router
vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
    refresh: vi.fn(),
  }),
  useSearchParams: () => ({
    get: vi.fn(),
  }),
  usePathname: () => '/test',
}));

// Mock Supabase
vi.mock('@/lib/supabase/client', () => ({
  createClient: () => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user: null } }),
      signInWithPassword: vi.fn(),
      signUp: vi.fn(),
      signOut: vi.fn(),
    },
    from: vi.fn(() => ({
      select: vi.fn().mockReturnThis(),
      insert: vi.fn().mockReturnThis(),
      update: vi.fn().mockReturnThis(),
      delete: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({ data: null }),
    })),
  }),
}));

// Mock environment variables
vi.mock('@/config/app-config', () => ({
  envValidation: {
    success: true,
    data: {
        NEXT_PUBLIC_SUPABASE_URL: 'http://localhost:54321',
        NEXT_PUBLIC_SUPABASE_ANON_KEY: 'test-key',
        SUPABASE_SERVICE_ROLE_KEY: 'test-service-key',
    }
  },
   config: {
    redis: {
      ttl: {}
    }
  }
}));

// Mock Redis
vi.mock('@/lib/redis', () => ({
  rateLimit: vi.fn().mockResolvedValue({ success: true }),
  redisClient: null,
  isRedisEnabled: false,
  invalidateCompanyCache: vi.fn().mockResolvedValue(undefined),
}));

// Mock logger
vi.mock('@/lib/logger', () => ({
  logger: {
    info: vi.fn(),
    error: vi.fn(),
    warn: vi.fn(),
    debug: vi.fn(),
  },
}));

vi.mock('@/lib/auth-helpers', async (importOriginal) => {
    const actual = await importOriginal();
    return {
        ...actual,
        getAuthContext: vi.fn().mockResolvedValue({
            userId: 'test-user-id',
            companyId: 'test-company-id',
        }),
    };
});


// Global test setup
beforeEach(() => {
  vi.clearAllMocks();
});
