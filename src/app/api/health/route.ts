import { NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { redisClient } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { testGenkitConnection } from '@/services/genkit';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { User } from '@/types';

export const dynamic = 'force-dynamic';

async function verifyAdminAuth(): Promise<{ authorized: boolean, error?: string, status?: number }> {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
            cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
        return { authorized: false, error: 'Authentication required.', status: 401 };
    }

    // Fetch the user's role from the public.users table (new location)
    const { data: profile, error } = await getServiceRoleClient()
        .from('users')
        .select('role')
        .eq('id', user.id)
        .single();
    
    if (error || !profile) {
        logger.error(`Could not verify user role for user ${user.id}`, error);
        return { authorized: false, error: 'Could not verify user role.', status: 500 };
    }

    if (profile.role !== 'Admin') {
        return { authorized: false, error: 'Forbidden: Requires admin privileges.', status: 403 };
    }

    return { authorized: true };
}


export async function GET() {
  const authResult = await verifyAdminAuth();
  if (!authResult.authorized) {
      return NextResponse.json({ error: authResult.error }, { status: authResult.status });
  }

  let dbStatus: 'healthy' | 'unhealthy' = 'unhealthy';
  let redisStatus: 'healthy' | 'unhealthy' | 'disabled' = 'unhealthy';
  let aiStatus: 'healthy' | 'unhealthy' = 'unhealthy';

  // Check Database Connection
  try {
    const supabase = getServiceRoleClient();
    const { error } = await supabase.from('users').select('id').limit(1);
    if (error) {
      throw error;
    }
    dbStatus = 'healthy';
  } catch (error: any) {
    logger.error('[Health Check] Database connection failed:', error.message);
  }

  // Check Redis Connection
  if (!process.env.REDIS_URL) {
    redisStatus = 'disabled';
  } else {
    try {
      const pingResponse = await redisClient.ping();
      if (pingResponse !== 'PONG') {
        throw new Error('Redis did not respond with PONG');
      }
      redisStatus = 'healthy';
    } catch (error: any) {
      logger.error('[Health Check] Redis connection failed:', error.message);
    }
  }

  // Check AI Service Connection
  try {
    const aiResult = await testGenkitConnection();
    if (aiResult.success) {
      aiStatus = 'healthy';
    } else {
      throw new Error(aiResult.error || 'AI service check failed.');
    }
  } catch(error: any) {
    logger.error('[Health Check] AI service connection failed:', error.message);
  }


  const isHealthy = dbStatus === 'healthy' && (redisStatus === 'healthy' || redisStatus === 'disabled') && aiStatus === 'healthy';

  return NextResponse.json(
    {
      status: isHealthy ? 'healthy' : 'unhealthy',
      checks: {
        database: dbStatus,
        cache: redisStatus,
        ai_service: aiStatus,
      },
      timestamp: new Date().toISOString(),
    },
    {
      status: isHealthy ? 200 : 503,
      headers: {
        'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      }
    }
  );
}
