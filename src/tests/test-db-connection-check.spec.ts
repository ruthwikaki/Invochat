import { test, expect } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

test.describe('Database Connection Check', () => {
  test('should connect to database and list tables', async () => {
    const supabase = createClient(supabaseUrl, supabaseKey);
    
    console.log('Connecting to:', supabaseUrl);
    
    // Test connection with a simple query first
    const { error: connectionError } = await supabase
      .from('purchase_orders')
      .select('count')
      .limit(1);
    
    if (connectionError) {
      console.log('Connection test failed:', connectionError);
      expect(connectionError).toBeNull();
      return;
    }
    
    console.log('Database connection: OK');

    // Test specific table access - using actual table names from the schema
    const testTables = ['companies', 'purchase_orders', 'suppliers', 'product_variants'];
    
    for (const tableName of testTables) {
      const { error: tableError } = await supabase
        .from(tableName)
        .select('*')
        .limit(1);
      
      if (tableError) {
        console.log(`Table ${tableName}: ERROR: ${tableError.message}`);
        // Only fail if it's a critical table
        if (['companies', 'purchase_orders'].includes(tableName)) {
          expect(tableError).toBeNull();
        }
      } else {
        console.log(`Table ${tableName}: OK`);
      }
    }
    
    // Ensure at least basic connectivity works
    expect(connectionError).toBeNull();
  });
});
