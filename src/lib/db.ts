import { Pool } from 'pg';

let pool: Pool;

// This file establishes a connection pool to your PostgreSQL database.
// It uses the environment variables defined in your .env file.

try {
    if (!process.env.POSTGRES_DATABASE) {
        throw new Error('POSTGRES_DATABASE environment variable is not set.');
    }

    pool = new Pool({
        user: process.env.POSTGRES_USER,
        host: process.env.POSTGRES_HOST,
        database: process.env.POSTGRES_DATABASE,
        password: process.env.POSTGRES_PASSWORD,
        port: parseInt(process.env.POSTGRES_PORT || '5432', 10),
        max: 20, // max number of clients in the pool
        idleTimeoutMillis: 30000, // how long a client is allowed to remain idle before being closed
        connectionTimeoutMillis: 2000, // how long to wait for a connection to be established
    });

    pool.on('connect', () => {
        console.log('PostgreSQL client connected to the pool');
    });

    pool.on('error', (err, client) => {
        console.error('Unexpected error on idle PostgreSQL client', err);
        process.exit(-1);
    });

} catch (error) {
    console.error("Failed to create PostgreSQL connection pool.", error);
    // Exit the process if the database connection fails to initialize.
    // This prevents the app from running in a broken state.
    process.exit(1);
}

export const db = pool;
