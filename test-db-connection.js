// Database connection test and fix
import { getServiceRoleClient } from '../src/lib/supabase/admin.js';
import * as fs from 'fs';
import * as path from 'path';

async function testDatabaseConnection() {
    console.log('🔍 Testing database connection...');
    
    try {
        const supabase = getServiceRoleClient();
        
        // Test basic connection
        const { data: companies, error: companyError } = await supabase
            .from('companies')
            .select('id, name')
            .limit(1);
            
        if (companyError) {
            console.error('❌ Company table query failed:', companyError);
            return false;
        }
        
        console.log('✅ Basic connection works. Found companies:', companies?.length || 0);
        
        // Test if get_dashboard_metrics function exists
        console.log('🔍 Testing get_dashboard_metrics function...');
        
        if (companies && companies.length > 0) {
            const { data: metricsData, error: metricsError } = await supabase
                .rpc('get_dashboard_metrics', {
                    p_company_id: companies[0].id,
                    p_days: 30
                });
                
            if (metricsError) {
                console.error('❌ get_dashboard_metrics failed:', metricsError);
                console.log('🔧 This is likely due to missing get_dead_stock_report function');
                return false;
            }
            
            console.log('✅ get_dashboard_metrics works!');
            return true;
        } else {
            console.log('⚠️ No companies found, cannot test metrics');
            return true; // Connection works, just no data
        }
        
    } catch (error) {
        console.error('❌ Database connection failed:', error);
        return false;
    }
}

async function applyDatabaseFix() {
    console.log('🔧 Applying database fix...');
    
    try {
        const supabase = getServiceRoleClient();
        const fixSql = fs.readFileSync(path.join(process.cwd(), 'fix_missing_dead_stock_function.sql'), 'utf8');
        
        // Execute the fix
        const { error } = await supabase.rpc('exec_sql', { sql: fixSql });
        
        if (error) {
            console.error('❌ Failed to apply fix:', error);
            return false;
        }
        
        console.log('✅ Database fix applied successfully');
        return true;
    } catch (error) {
        console.error('❌ Error applying fix:', error);
        return false;
    }
}

async function main() {
    console.log('🚀 Starting database diagnosis...');
    
    const connectionWorks = await testDatabaseConnection();
    
    if (!connectionWorks) {
        console.log('🔧 Attempting to fix database...');
        await applyDatabaseFix();
        
        // Test again
        console.log('🔍 Testing after fix...');
        await testDatabaseConnection();
    }
}

main().catch(console.error);
