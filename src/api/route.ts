
import { NextResponse } from 'next/server';

// A default response for the /api root.
export async function GET() {
  return NextResponse.json({ message: 'AIventory API is running.' });
}
