
import { testSupabaseConnection, testDatabaseQuery, testGenkitConnection, testMaterializedView, testRedisConnection, getInventoryConsistencyReport, getFinancialConsistencyReport } from '@/app/data-actions';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { AlertTriangle, CheckCircle, Database, HelpCircle, Bot, Zap, Redis, ShieldCheck } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import type { HealthCheckResult } from '@/types';

async function TestResultItem({ title, success, helpText, testId, errorText, isEnabled = true }: { title: string, success: boolean, helpText?: string, testId: number, errorText?: string | null, isEnabled?: boolean }) {
  let status: 'pass' | 'fail' | 'skipped' = 'fail';
  if (!isEnabled) {
    status = 'skipped';
  } else if (success) {
    status = 'pass';
  }

  const badgeVariant = {
    pass: 'default',
    fail: 'destructive',
    skipped: 'secondary',
  }[status] as 'default' | 'destructive' | 'secondary';

  const statusText = {
    pass: 'Pass',
    fail: 'Fail',
    skipped: 'Skipped',
  }[status];

  return (
    <div className="flex flex-col items-start gap-1 rounded-lg border p-3">
        <div className="flex w-full items-center justify-between">
            <div className="flex items-center gap-2">
                <span className="font-medium">{testId}. {title}</span>
                {helpText && <HelpCircle className="h-4 w-4 text-muted-foreground" title={helpText} />}
            </div>
            <Badge variant={badgeVariant}>
                {statusText}
            </Badge>
        </div>
        {status === 'fail' && errorText && <p className="text-xs text-destructive pl-5">{errorText}</p>}
        {status === 'skipped' && errorText && <p className="text-xs text-muted-foreground pl-5">{errorText}</p>}
    </div>
  )
}

function DataIntegrityCheckItem({ title, result }: { title: string, result: HealthCheckResult }) {
  const status = result.healthy ? 'pass' : 'fail';
  const badgeVariant = status === 'pass' ? 'default' : 'destructive';
  const statusText = status === 'pass' ? 'Healthy' : 'Error';

  return (
    <div className="flex flex-col items-start gap-1 rounded-lg border p-3">
        <div className="flex w-full items-center justify-between">
            <div className="font-medium">{title}</div>
            <Badge variant={badgeVariant}>
                {statusText}
            </Badge>
        </div>
        <p className="text-xs text-muted-foreground pl-1">{result.message}</p>
    </div>
  );
}


export default async function SystemHealthPage() {
  const [
    supabaseConnection, 
    databaseQuery, 
    genkitConnection, 
    materializedView, 
    redisConnection, 
    inventoryConsistency, 
    financialConsistency
  ] = await Promise.all([
      testSupabaseConnection(),
      testDatabaseQuery(),
      testGenkitConnection(),
      testMaterializedView(),
      testRedisConnection(),
      getInventoryConsistencyReport(),
      getFinancialConsistencyReport()
  ]);

  return (
    <AppPage>
      <AppPageHeader 
        title="System Health Check"
        description="This page runs a series of tests to diagnose the health of your application's core services."
      />

       <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-3">
            <ShieldCheck className="h-6 w-6 text-primary" />
            Data Integrity Checks
          </CardTitle>
          <CardDescription>These checks verify the internal consistency of your business data.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
            <DataIntegrityCheckItem title="Inventory Quantity Consistency" result={inventoryConsistency} />
            <DataIntegrityCheckItem title="Sales Financial Consistency" result={financialConsistency} />
        </CardContent>
      </Card>
      
      {/* Supabase Tests */}
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-3">
            <Database className="h-6 w-6 text-primary" />
            Supabase Health
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
            <TestResultItem testId={1} title="Credentials Configured" success={supabaseConnection.isConfigured} errorText={supabaseConnection.error?.message} />
            <TestResultItem testId={2} title="API Connection Successful" success={supabaseConnection.success} errorText={supabaseConnection.error?.message} />
            <TestResultItem testId={3} title="Authenticated User Found" success={!!supabaseConnection.user} />
            <TestResultItem testId={4} title="Database Query Test" success={databaseQuery.success} errorText={databaseQuery.error} helpText="Tests if the server can query the 'inventory' table using the Service Role Key." />
            <TestResultItem testId={5} title="Performance View Exists" success={materializedView.success} errorText={materializedView.error} helpText="Checks for the 'company_dashboard_metrics' view, which speeds up the dashboard." />
            
            {supabaseConnection.error && !supabaseConnection.isConfigured && (
              <div>
                <h3 className="font-semibold mb-2 text-destructive">Supabase API Error:</h3>
                <pre className="bg-muted p-4 rounded-md text-sm text-destructive font-mono overflow-auto">
                  {supabaseConnection.error.message}
                </pre>
              </div>
            )}
            
            {databaseQuery.error && (
                <div>
                <h3 className="font-semibold mb-2 text-destructive">Database Query Error:</h3>
                <pre className="bg-muted p-4 rounded-md text-sm text-destructive font-mono overflow-auto">
                    {databaseQuery.error}
                </pre>
                </div>
            )}
        </CardContent>
      </Card>
      
      {/* Genkit Tests */}
      <Card>
        <CardHeader>
            <CardTitle className="flex items-center gap-3">
                <Bot className="h-6 w-6 text-primary" />
                Google AI / Genkit Health
            </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
            <TestResultItem testId={6} title="GOOGLE_API_KEY Configured" success={genkitConnection.isConfigured} errorText={genkitConnection.error} />
            <TestResultItem testId={7} title="Genkit API Call Successful" success={genkitConnection.success} errorText={genkitConnection.error} helpText="Attempts a simple text generation call to verify the API key and model access." />

            {genkitConnection.error && !genkitConnection.isConfigured && (
                <div>
                <h3 className="font-semibold mb-2 text-destructive">Genkit Error Details:</h3>
                <pre className="bg-muted p-4 rounded-md text-sm text-destructive font-mono overflow-auto">
                    {genkitConnection.error}
                </pre>
                </div>
            )}
        </CardContent>
      </Card>

      {/* Redis Test */}
      <Card>
        <CardHeader>
            <CardTitle className="flex items-center gap-3">
                <Redis className="h-6 w-6 text-primary" />
                Redis Health
            </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
            <TestResultItem 
              testId={8} 
              title="Redis Connection" 
              success={redisConnection.success} 
              errorText={redisConnection.error}
              isEnabled={redisConnection.isEnabled}
              helpText="Tests if the app can connect to the Redis server for caching and rate limiting."
            />
        </CardContent>
      </Card>

      {/* Summary / User Details Card */}
       <Card>
        <CardHeader>
            <CardTitle>Configuration Summary</CardTitle>
        </CardHeader>
        <CardContent>
            {supabaseConnection.user ? (
                <div>
                    <h3 className="font-semibold mb-2">Authenticated User Details:</h3>
                    <div className="bg-muted p-4 rounded-md text-sm font-mono overflow-auto">
                        <p><strong>Email:</strong> {supabaseConnection.user.email}</p>
                        <p><strong>Company ID:</strong> {supabaseConnection.user.app_metadata?.company_id || 'Not Found'}</p>
                    </div>
                </div>
            ) : (
                <p className="text-muted-foreground">No authenticated user session found.</p>
            )}
        </CardContent>
        <CardFooter className="bg-muted/50 p-4 rounded-b-lg">
            <div className="flex items-start gap-3">
                 <HelpCircle className="h-5 w-5 text-muted-foreground mt-1"/>
                 <div>
                    <h4 className="font-semibold">What does this mean?</h4>
                    <p className="text-sm text-muted-foreground">If all tests pass but you still experience issues, it might be related to data-specific problems. For example, a successful database query test with zero results means your tables might be empty for your company. Consider using the "Import Data" page.</p>
                 </div>
            </div>
        </CardFooter>
      </Card>
    </AppPage>
  );
}
