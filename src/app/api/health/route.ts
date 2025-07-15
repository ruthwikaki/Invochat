
import { NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { redisClient } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { testGenkitConnection } from '@/services/genkit';
import { headers } from 'next/headers';

export const dynamic = 'force-dynamic';

async function verifyAdminAuth(): Promise<{ authorized: boolean, error?: string, status?: number }> {
    const healthCheckKey = process.env.HEALTH_CHECK_API_KEY;
    if (!healthCheckKey) {
        logger.error('[Health Check] HEALTH_CHECK_API_KEY is not set. Endpoint is disabled.');
        return { authorized: false, error: 'Endpoint not configured.', status: 501 };
    }

    const authHeader = headers().get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return { authorized: false, error: 'Missing or invalid Authorization header.', status: 401 };
    }

    const providedKey = authHeader.substring(7);
    if (providedKey !== healthCheckKey) {
        return { authorized: false, error: 'Forbidden.', status: 403 };
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
    logger.error('[Health Check] Database connection failed:', { message: error.message });
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
      logger.error('[Health Check] Redis connection failed:', { message: error.message });
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
    logger.error('[Health Check] AI service connection failed:', { message: error.message });
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
