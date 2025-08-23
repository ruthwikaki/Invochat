const { createClient } = require('@supabase/supabase-js')
const fs = require('fs')
require('dotenv').config({ path: '.env.local' })

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
)

async function applySqlFix () {
  try {
    console.log('🔧 Applying SQL fix for forecast_demand function...')

    const sqlContent = fs.readFileSync('fix_forecast_function.sql', 'utf8')

    // Execute the SQL to fix the function
    const { data, error } = await supabase.rpc('exec_sql', { sql: sqlContent })

    if (error) {
      // Try direct execution if exec_sql doesn't exist
      console.log('Trying direct query execution...')

      const { data: directData, error: directError } = await supabase
        .from('_temp') // This will fail but we can use .sql() if available
        .select('1')
        .limit(1)

      console.log('Direct approach not available, applying via manual execution...')

      // Let's test if the function works after our theoretical fix
      const companyId = 'c7c38f2a-77c8-48c7-b7a8-5577e4aecd36'

      const { data: testData, error: testError } = await supabase
        .rpc('forecast_demand', { p_company_id: companyId })

      if (testError) {
        console.log('❌ Function still has error:', testError.message)
        console.log('\n📋 The SQL function needs to be manually fixed in the database.')
        console.log('Please run this SQL in your Supabase SQL editor:')
        console.log('\n' + sqlContent)
      } else {
        console.log('✅ Function is working! Returned:', testData?.length || 0, 'results')
      }
    } else {
      console.log('✅ SQL fix applied successfully')
    }
  } catch (error) {
    console.error('❌ Failed to apply SQL fix:', error.message)

    // Show the SQL that needs to be run manually
    const sqlContent = fs.readFileSync('fix_forecast_function.sql', 'utf8')
    console.log('\n📋 Please manually run this SQL in Supabase SQL editor:')
    console.log('\n' + sqlContent)
  }
}

applySqlFix()
