
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

// We now export the test as a function to be called explicitly from the root layout.
export async function testDbConnection() {
    if (connectionTested || !process.env.POSTGRES_DATABASE) return;

    let client;
    try {
        console.log('[DB Test] Attempting to connect to PostgreSQL...');
        client = await db.connect();
        const res = await client.query('SELECT NOW()');
        console.log(`[DB Test] ✅ Connection successful. Database time is: ${res.rows[0].now}`);
        connectionTested = true;
    } catch (err: any) {
        console.error('[DB Test] ❌ Connection failed. Please check your .env file and ensure PostgreSQL is running.');
        if (err.code) {
          console.error(`[DB Test] Hint: A specific error code was returned: ${err.code}.`);
          if(err.code === 'ECONNREFUSED') {
            console.error(`[DB Test] This code often means the PostgreSQL server is not running or is not accessible at ${process.env.POSTGRES_HOST}:${process.env.POSTGRES_PORT}.`);
          }
          if(err.code === '28P01') {
             console.error(`[DB Test] This code (auth_spec_failed) can mean the user or password in your .env file is incorrect.`);
          }
          if(err.code === '3D000') {
             console.error(`[DB Test] This code (invalid_catalog_name) means the database "${process.env.POSTGRES_DATABASE}" does not exist.`);
          }
        }
    } finally {
        if (client) {
            client.release();
        }
    }
}
