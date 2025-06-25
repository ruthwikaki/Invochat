
import { handleAuth } from '@supabase/auth-helpers-nextjs';

export const dynamic = 'force-dynamic';

export const { GET, POST } = handleAuth();
