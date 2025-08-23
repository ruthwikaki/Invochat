'use server';

/**
 * API Performance Optimization Middleware
 * Part of Technical Infrastructure Improvements - Phase 3
 */

import { NextRequest } from 'next/server';
import { getCache, setCache, incrementCounter } from '@/services/advanced-cache-service';
import { logError } from '@/lib/error-handler';

// Rate limiting configuration
interface RateLimitConfig {
  windowMs: number; // Time window in milliseconds
  maxRequests: number; // Max requests per window
  skipSuccessfulRequests?: boolean;
  skipFailedRequests?: boolean;
}

// API performance metrics
interface ApiMetrics {
  endpoint: string;
  method: string;
  responseTime: number;
  statusCode: number;
  timestamp: Date;
  userAgent?: string;
  ip?: string;
}

// Default rate limit configurations for different endpoint types
const RATE_LIMIT_CONFIGS: Record<string, RateLimitConfig> = {
  'api-analytics': { windowMs: 60000, maxRequests: 100 }, // 100 requests per minute
  'api-inventory': { windowMs: 60000, maxRequests: 200 }, // 200 requests per minute
  'api-auth': { windowMs: 60000, maxRequests: 20 }, // 20 requests per minute
  'api-integrations': { windowMs: 60000, maxRequests: 50 }, // 50 requests per minute
  'api-default': { windowMs: 60000, maxRequests: 150 } // Default limit
};

// Response compression types (for future use)
// const COMPRESSIBLE_TYPES = [
//   'application/json',
//   'text/html',
//   'text/plain',
//   'text/css',
//   'application/javascript'
// ];

class ApiPerformanceOptimizer {
  private static instance: ApiPerformanceOptimizer;
  private metrics: Map<string, ApiMetrics[]> = new Map();

  static getInstance(): ApiPerformanceOptimizer {
    if (!ApiPerformanceOptimizer.instance) {
      ApiPerformanceOptimizer.instance = new ApiPerformanceOptimizer();
    }
    return ApiPerformanceOptimizer.instance;
  }

  // Rate limiting middleware
  async rateLimit(request: NextRequest, config?: RateLimitConfig): Promise<{ allowed: boolean; remaining: number; resetTime: number }> {
    const ip = this.getClientIp(request);
    const endpoint = this.getEndpointCategory(request.nextUrl.pathname);
    const rateLimitConfig = config || RATE_LIMIT_CONFIGS[endpoint] || RATE_LIMIT_CONFIGS['api-default'];
    
    const key = `rate_limit:${endpoint}:${ip}`;
    const windowMs = rateLimitConfig.windowMs;
    const maxRequests = rateLimitConfig.maxRequests;
    
    try {
      // Increment request counter
      const currentCount = await incrementCounter(key, 1, Math.ceil(windowMs / 1000));
      
      const allowed = currentCount <= maxRequests;
      const remaining = Math.max(0, maxRequests - currentCount);
      const resetTime = Date.now() + windowMs;

      return { allowed, remaining, resetTime };
    } catch (error) {
      logError('Rate limiting failed', error as Error);
      // Fail open - allow request if rate limiting fails
      return { allowed: true, remaining: maxRequests, resetTime: Date.now() + windowMs };
    }
  }

  // Response caching middleware
  async checkCache(request: NextRequest): Promise<Response | null> {
    // Only cache GET requests
    if (request.method !== 'GET') return null;

    const url = request.nextUrl;
    const cacheKey = `api_cache:${url.pathname}:${url.search}`;
    
    try {
      const cached = await getCache<{
        body: string;
        headers: Record<string, string>;
        status: number;
      }>(cacheKey, 'analytics');

      if (cached) {
        const response = new Response(cached.body, {
          status: cached.status,
          headers: {
            ...cached.headers,
            'X-Cache': 'HIT',
            'Cache-Control': 'public, max-age=300'
          }
        });
        return response;
      }
    } catch (error) {
      logError('Cache check failed', error as Error);
    }

    return null;
  }

  // Cache response
  async cacheResponse(request: NextRequest, response: Response, _ttl: number = 300): Promise<void> {
    // Only cache successful GET requests
    if (request.method !== 'GET' || response.status >= 400) return;

    const url = request.nextUrl;
    const cacheKey = `api_cache:${url.pathname}:${url.search}`;
    
    try {
      // Clone response to read body
      const responseClone = response.clone();
      const body = await responseClone.text();
      
      const cacheData = {
        body,
        headers: Object.fromEntries(response.headers.entries()),
        status: response.status
      };

      await setCache(cacheKey, cacheData, 'analytics');
    } catch (error) {
      logError('Response caching failed', error as Error);
    }
  }

  // Log API metrics
  logMetrics(request: NextRequest, response: Response, startTime: number): void {
    const endpoint = request.nextUrl.pathname;
    const method = request.method;
    const responseTime = Date.now() - startTime;
    const statusCode = response.status;
    
    const metrics: ApiMetrics = {
      endpoint,
      method,
      responseTime,
      statusCode,
      timestamp: new Date(),
      userAgent: request.headers.get('user-agent') || undefined,
      ip: this.getClientIp(request)
    };

    // Store metrics in memory (in production, send to monitoring service)
    if (!this.metrics.has(endpoint)) {
      this.metrics.set(endpoint, []);
    }
    
    const endpointMetrics = this.metrics.get(endpoint)!;
    endpointMetrics.push(metrics);
    
    // Keep only last 100 metrics per endpoint
    if (endpointMetrics.length > 100) {
      endpointMetrics.splice(0, endpointMetrics.length - 100);
    }

    // Log slow requests
    if (responseTime > 1000) {
      console.warn('Slow API request detected:', {
        endpoint,
        method,
        responseTime,
        statusCode
      });
    }
  }

  // Get endpoint category for rate limiting
  private getEndpointCategory(pathname: string): string {
    if (pathname.startsWith('/api/analytics')) return 'api-analytics';
    if (pathname.startsWith('/api/inventory')) return 'api-inventory';
    if (pathname.startsWith('/api/auth')) return 'api-auth';
    if (pathname.startsWith('/api/integrations')) return 'api-integrations';
    return 'api-default';
  }

  // Extract client IP
  private getClientIp(request: NextRequest): string {
    const forwarded = request.headers.get('x-forwarded-for');
    if (forwarded) {
      return forwarded.split(',')[0].trim();
    }
    
    return request.headers.get('x-real-ip') || 
           request.headers.get('x-client-ip') || 
           request.ip || 
           'unknown';
  }

  // Get metrics for monitoring
  getMetrics(): Record<string, ApiMetrics[]> {
    return Object.fromEntries(this.metrics.entries());
  }

  // Get performance summary
  getPerformanceSummary(): Record<string, {
    totalRequests: number;
    avgResponseTime: number;
    errorRate: number;
    slowRequestCount: number;
  }> {
    const summary: Record<string, any> = {};

    for (const [endpoint, metrics] of this.metrics.entries()) {
      const totalRequests = metrics.length;
      const avgResponseTime = metrics.reduce((sum, m) => sum + m.responseTime, 0) / totalRequests;
      const errorCount = metrics.filter(m => m.statusCode >= 400).length;
      const errorRate = (errorCount / totalRequests) * 100;
      const slowRequestCount = metrics.filter(m => m.responseTime > 1000).length;

      summary[endpoint] = {
        totalRequests,
        avgResponseTime: Math.round(avgResponseTime),
        errorRate: Math.round(errorRate * 100) / 100,
        slowRequestCount
      };
    }

    return summary;
  }
}

// Middleware function to wrap API routes
export async function withPerformanceOptimization(
  request: NextRequest,
  handler: (req: NextRequest) => Promise<Response>,
  options?: {
    enableRateLimit?: boolean;
    enableCaching?: boolean;
    rateLimitConfig?: RateLimitConfig;
    cacheTtl?: number;
  }
): Promise<Response> {
  const optimizer = ApiPerformanceOptimizer.getInstance();
  const startTime = Date.now();
  const opts = {
    enableRateLimit: true,
    enableCaching: true,
    cacheTtl: 300,
    ...options
  };

  try {
    // Rate limiting
    if (opts.enableRateLimit) {
      const rateLimitResult = await optimizer.rateLimit(request, opts.rateLimitConfig);
      
      if (!rateLimitResult.allowed) {
        const response = new Response(
          JSON.stringify({
            error: 'Rate limit exceeded',
            retryAfter: Math.ceil((rateLimitResult.resetTime - Date.now()) / 1000)
          }),
          {
            status: 429,
            headers: {
              'Content-Type': 'application/json',
              'X-RateLimit-Limit': String(opts.rateLimitConfig?.maxRequests || 150),
              'X-RateLimit-Remaining': String(rateLimitResult.remaining),
              'X-RateLimit-Reset': String(rateLimitResult.resetTime),
              'Retry-After': String(Math.ceil((rateLimitResult.resetTime - Date.now()) / 1000))
            }
          }
        );
        
        optimizer.logMetrics(request, response, startTime);
        return response;
      }
    }

    // Check cache
    if (opts.enableCaching) {
      const cachedResponse = await optimizer.checkCache(request);
      if (cachedResponse) {
        optimizer.logMetrics(request, cachedResponse, startTime);
        return cachedResponse;
      }
    }

    // Execute handler
    const response = await handler(request);

    // Cache response
    if (opts.enableCaching && response.status < 400) {
      await optimizer.cacheResponse(request, response, opts.cacheTtl);
      
      // Add cache headers
      response.headers.set('X-Cache', 'MISS');
      response.headers.set('Cache-Control', `public, max-age=${opts.cacheTtl}`);
    }

    // Add performance headers
    response.headers.set('X-Response-Time', `${Date.now() - startTime}ms`);
    response.headers.set('X-API-Version', '1.0');

    // Log metrics
    optimizer.logMetrics(request, response, startTime);

    return response;

  } catch (error) {
    logError('API performance optimization error', error as Error);
    
    const errorResponse = new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      }
    );

    optimizer.logMetrics(request, errorResponse, startTime);
    return errorResponse;
  }
}

// Export the optimizer for direct access
export { ApiPerformanceOptimizer };
