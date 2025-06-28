
import { testSupabaseConnection, testDatabaseQuery, testGenkitConnection, testMaterializedView } from '@/app/data-actions';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { AlertCircle, CheckCircle, Database, HelpCircle, Bot, Zap } from 'lucide-react';

async function TestResultItem({ title, success, helpText, testId, errorText }: { title: string, success: boolean, helpText?: string, testId: number, errorText?: string | null }) {
  return (
    <div className="flex flex-col items-start gap-1 rounded-lg border p-3">
        <div className="flex w-full items-center justify-between">
            <div className="flex items-center gap-2">
                <span className="font-medium">{testId}. {title}</span>
                {helpText && <HelpCircle className="h-4 w-4 text-muted-foreground" title={helpText} />}
            </div>
            <Badge variant={success ? 'default' : 'destructive'}>
                {success ? 'Pass' : 'Fail'}
            </Badge>
        </div>
        {!success && errorText && <p className="text-xs text-destructive pl-5">{errorText}</p>}
    </div>
  )
}

export default async function SystemHealthPage() {
  const supabaseConnection = await testSupabaseConnection();
  const databaseQuery = await testDatabaseQuery();
  const genkitConnection = await testGenkitConnection();
  const materializedView = await testMaterializedView();

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center gap-2">
        <SidebarTrigger className="md:hidden" />
        <h1 className="text-2xl font-semibold">System Health Check</h1>
      </div>
      <CardDescription>
        This page runs a series of tests to diagnose the health of your application's core services.
      </CardDescription>

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
    </div>
  );
}
