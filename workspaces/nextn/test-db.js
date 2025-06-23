// This is a diagnostic script to test the PostgreSQL connection directly.
// To use it, run `node test-db.js` in your terminal from within the 'workspaces/nextn' directory.

require('dotenv').config({ path: require('path').join(__dirname, '../.env') });
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
    const dbName = process.env.POSTGRES_DATABASE || '(not set)';
    const dbHost = process.env.POSTGRES_HOST || '(not set)';
    const dbPort = process.env.POSTGRES_PORT || '(not set)';
    const dbUser = process.env.POSTGRES_USER || '(not set)';

    if (dbName === '(not set)' || dbHost === '(not set)') {
        console.error('\n❌ Failure! Environment variables not loaded.');
        console.error('   Please ensure your .env file exists in the project root and contains the POSTGRES_* variables.');
        return;
    }


    console.log(`[Test Script] Attempting to connect to database "${dbName}" on ${dbHost}:${dbPort}...`);
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
        console.error(`  1. Are the credentials in your .env file correct (user: "${dbUser}", password, host: "${dbHost}", port: "${dbPort}", database: "${dbName}")?`);
        console.error(`  2. Is your PostgreSQL server configured to accept connections from user "${dbUser}" on database "${dbName}"?`);
        console.error('  3. Is there a firewall blocking the connection?\n');
    } finally {
        if (client) {
            client.release();
        }
        await pool.end();
    }
}

testConnection();
