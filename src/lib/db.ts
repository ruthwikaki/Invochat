
import { Pool } from 'pg';

// This file establishes a connection pool to your PostgreSQL database.
// It uses the environment variables defined in your .env file.
// It also includes a self-testing function to verify the connection on startup.

if (!process.env.POSTGRES_DATABASE) {
    console.warn('[DB] POSTGRES_DATABASE environment variable is not set. Database features will be unavailable.');
}

const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: process.env.POSTGRES_PASSWORD,
    port: parseInt(process.env.POSTGRES_PORT || '5432', 10),
    max: 20, // max number of clients in the pool
    idleTimeoutMillis: 30000, // how long a client is allowed to remain idle before being closed
    connectionTimeoutMillis: 2000, // how long to wait for a connection to be established
});

pool.on('error', (err, client) => {
    console.error('Unexpected error on idle PostgreSQL client', err);
});

export const db = pool;

let connectionTested = false;
let dbIsConnected = false;

// We now export the test as a function to be called explicitly from the root layout.
export async function testDbConnection() {
    if (connectionTested || !process.env.POSTGRES_DATABASE) return;
    connectionTested = true; // Mark as tested, so we don't retry on every hot-reload.

    let client;
    try {
        console.log('[DB] Attempting to connect to PostgreSQL...');
        client = await db.connect();
        const res = await client.query('SELECT NOW()');
        console.log(`[DB] ✅ Connection successful. Database time is: ${res.rows[0].now}`);
        dbIsConnected = true;
    } catch (err: any) {
        console.warn('---');
        console.warn('[DB] ⚠️  Could not connect to PostgreSQL database.');
        console.warn(`[DB] This is expected if you haven't started your local database server.`);
        console.warn(`[DB] The application will continue to run, but data-dependent features will be empty.`);
        console.warn(`[DB] To enable database features, start PostgreSQL and restart the app.`);
        console.warn('---');
        dbIsConnected = false;
    } finally {
        if (client) {
            client.release();
        }
    }
}

export const isDbConnected = () => dbIsConnected;
