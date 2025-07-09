

import { NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { redisClient } from '@/lib/redis';
import { logger } from '@/lib/logger';

export const dynamic = 'force-dynamic';

export async function GET() {
  let dbStatus: 'healthy' | 'unhealthy' = 'unhealthy';
  let redisStatus: 'healthy' | 'unhealthy' | 'disabled' = 'unhealthy';

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

  const isHealthy = dbStatus === 'healthy' && (redisStatus === 'healthy' || redisStatus === 'disabled');

  return NextResponse.json(
    {
      status: isHealthy ? 'healthy' : 'unhealthy',
      checks: {
        database: dbStatus,
        cache: redisStatus,
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
