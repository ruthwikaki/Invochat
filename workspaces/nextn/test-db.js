// This is a diagnostic script to test the PostgreSQL connection directly.
// To use it, run `node test-db.js` in your terminal from within the 'workspaces/nextn' directory.

const path = require('path');
const fs = require('fs');

const envPath = path.join(__dirname, '../../.env');

// 1. Check if the .env file exists
if (!fs.existsSync(envPath)) {
    console.error(`\n❌ Failure! The .env file was not found at the expected path: ${envPath}`);
    console.error('   Please ensure the .env file exists in the project root directory.');
    return;
}

// 2. Load environment variables
require('dotenv').config({ path: envPath });
const { Pool } = require('pg');

const pool = new Pool({
    user: process.env.POSTGRES_USER,
    host: process.env.POSTGRES_HOST,
    database: process.env.POSTGRES_DATABASE,
    password: process.env.POSTGRES_PASSWORD,
    port: parseInt(process.env.POSTGRES_PORT || '5432', 10),
    connectionTimeoutMillis: 5000, // 5 second timeout
});

async function testConnection() {
    const dbName = process.env.POSTGRES_DATABASE;
    const dbHost = process.env.POSTGRES_HOST;
    const dbPort = process.env.POSTGRES_PORT;
    const dbUser = process.env.POSTGRES_USER;
    const dbPassword = process.env.POSTGRES_PASSWORD ? '******' : '(not set)';

    console.log(`\n[Test Script] Loaded config from: ${envPath}`);
    console.log('[Test Script] ---------------');
    console.log(`[Test Script] Host:     ${dbHost}`);
    console.log(`[Test Script] Port:     ${dbPort}`);
    console.log(`[Test Script] Database: ${dbName}`);
    console.log(`[Test Script] User:     ${dbUser}`);
    console.log(`[Test Script] Password: ${dbPassword}`);
    console.log('[Test Script] ---------------');


    if (!dbName || !dbHost || !dbPort || !dbUser || !process.env.POSTGRES_PASSWORD) {
        console.error('\n❌ Failure! One or more POSTGRES_* variables are missing or empty in your .env file.');
        console.error('   Please fill in POSTGRES_HOST, PORT, USER, PASSWORD, and DATABASE.');
        return;
    }

    console.log(`\n[Test Script] Attempting to connect...`);
    let client;
    try {
        client = await pool.connect();
        const res = await client.query('SELECT NOW()');
        console.log('\n✅ Success! Connection to PostgreSQL was successful.');
        console.log('   Database server time is:', res.rows[0].now);
        console.log('   You can now restart your main application with `npm run dev`.\n');
    } catch (err) {
        console.error('\n❌ Failure! Could not connect to PostgreSQL.');
        console.error('   The specific error is:', err.message);
        console.error('\nPlease check the following:');
        console.error(`  1. Are the credentials in your .env file correct?`);
        console.error(`  2. Is your PostgreSQL server running and configured to accept connections for user "${dbUser}" on database "${dbName}"?`);
        console.error('  3. Is there a firewall blocking the connection?\n');
    } finally {
        if (client) {
            client.release();
        }
        await pool.end();
    }
}

testConnection();
