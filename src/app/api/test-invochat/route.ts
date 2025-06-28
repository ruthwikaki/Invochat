// This file is deprecated and has been replaced by the System Health page.
// It can be safely deleted from your project.
import { NextResponse } from 'next/server';

export async function GET() {
    return NextResponse.json({ 
        message: 'This API route is deprecated and can be deleted.' 
    }, { status: 410 });
}
