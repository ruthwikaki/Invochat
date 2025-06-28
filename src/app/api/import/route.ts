
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { type NextRequest, NextResponse } from 'next/server';

export async function POST(request: NextRequest) {
    // This route is now deprecated as the 'products' table, which it relied on, has been removed.
    // Data should now be synced via direct platform connections.
    return NextResponse.json({ 
        error: 'This feature is deprecated. Please use a direct platform integration to sync your data.' 
    }, { status: 400 });
}
