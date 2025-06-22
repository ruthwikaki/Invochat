// This is a diagnostic script to test the PostgreSQL connection directly.
// To use it, run `node test-db.js` in your terminal from within the 'workspaces/nextn' directory.

require('dotenv').config({ path: '.env.local' });
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
    console.log(`[Test Script] Attempting to connect to database "${process.env.POSTGRES_DATABASE}" on ${process.env.POSTGRES_HOST}:${process.env.POSTGRES_PORT}...`);
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
        console.error('  1. Are the credentials in your .env.local file correct (user, password, host, port, database name)?');
        console.error('  2. Is your PostgreSQL server configured to accept connections from user "' + process.env.POSTGRES_USER + '" on database "' + process.env.POSTGRES_DATABASE + '"?');
        console.error('  3. Is there a firewall blocking the connection?\n');
    } finally {
        if (client) {
            client.release();
        }
        await pool.end();
    }
}

testConnection();
