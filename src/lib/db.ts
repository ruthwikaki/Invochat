
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
    console.warn('[DB] Supabase environment variables are not set. Database features will be unavailable.');
}

export const supabase = createClient(supabaseUrl!, supabaseAnonKey!);

export const isDbConnected = () => {
    return !!(supabaseUrl && supabaseAnonKey);
};

export async function testDbConnection() {
    if (!isDbConnected()) {
        console.warn('---');
        console.warn('[DB] Running in Mock Data Mode. Supabase environment variables are not fully set.');
        console.warn('[DB] The application will use sample data and will not connect to a database.');
        console.warn('---');
        return;
    }
    // We don't need a connection test like with pg. The first query will test it.
    console.log('[DB] Supabase client configured.');
}
