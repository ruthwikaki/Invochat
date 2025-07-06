
/**
 * @fileoverview This API route is deprecated.
 * All chat functionality is now handled by the server action in `src/app/actions.ts`.
 * This file is kept to prevent 404 errors but should not be used.
 */
import { NextResponse } from 'next/server';

export async function POST(req: Request) {
  return NextResponse.json(
    { error: 'This endpoint is deprecated. Please use the appropriate server action.' },
    { status: 410 } // 410 Gone
  );
}
