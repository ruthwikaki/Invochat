
import { NextResponse } from 'next/server';

// A default response for the /api root.
export async function GET() {
  return NextResponse.json({ message: 'InvoChat API is running.' });
}
