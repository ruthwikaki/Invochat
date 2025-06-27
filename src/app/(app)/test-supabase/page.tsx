
import { testSupabaseConnection, testDatabaseQuery } from '@/app/data-actions';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { AlertCircle, CheckCircle, Database, HelpCircle } from 'lucide-react';

export default async function TestSupabasePage() {
  const { success: connectionSuccess, error: connectionError, user, isConfigured } = await testSupabaseConnection();
  const queryResult = await testDatabaseQuery();

  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center gap-2">
        <SidebarTrigger className="md:hidden" />
        <h1 className="text-2xl font-semibold">Supabase Connection Test</h1>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-3">
            {connectionSuccess ? <CheckCircle className="h-6 w-6 text-success" /> : <AlertCircle className="h-6 w-6 text-destructive" />}
            Connection Health
          </CardTitle>
          <CardDescription>
            This page tests the connection to your Supabase instance from the server.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between rounded-lg border p-3">
            <span className="font-medium">1. Credentials Configured</span>
             <Badge variant={isConfigured ? 'default' : 'destructive'}>
                {isConfigured ? 'Yes' : 'No'}
             </Badge>
          </div>
          
           <div className="flex items-center justify-between rounded-lg border p-3">
            <span className="font-medium">2. API Connection Successful</span>
             <Badge variant={connectionSuccess ? 'default' : 'destructive'}>
                {connectionSuccess ? 'Yes' : 'No'}
             </Badge>
          </div>
          
           <div className="flex items-center justify-between rounded-lg border p-3">
            <span className="font-medium">3. Authenticated User Found</span>
             <Badge variant={user ? 'default' : 'secondary'}>
                {user ? 'Yes' : 'No'}
             </Badge>
          </div>

          <div className="flex items-center justify-between rounded-lg border p-3">
            <div className="flex items-center gap-2" title="Tests if the server can query the 'inventory' table using the Service Role Key.">
                <span className="font-medium">4. Database Query Test</span>
                <HelpCircle className="h-4 w-4 text-muted-foreground" />
            </div>
             <Badge variant={queryResult.success ? 'default' : 'destructive'}>
                {queryResult.success ? 'Yes' : 'No'}
             </Badge>
          </div>

          {connectionError && (
            <div>
              <h3 className="font-semibold mb-2 text-destructive">API Connection Error Details:</h3>
              <pre className="bg-muted p-4 rounded-md text-sm text-destructive font-mono overflow-auto">
                {JSON.stringify(connectionError, null, 2)}
              </pre>
            </div>
          )}
          
          {user && (
             <div>
              <h3 className="font-semibold mb-2">Authenticated User Details:</h3>
              <div className="bg-muted p-4 rounded-md text-sm font-mono overflow-auto">
                <p><strong>Email:</strong> {user.email}</p>
                <p><strong>Company ID:</strong> {user.app_metadata?.company_id || 'Not Found'}</p>
              </div>
            </div>
          )}
          
          {queryResult.error ? (
             <div>
              <h3 className="font-semibold mb-2 text-destructive">Database Query Error:</h3>
              <pre className="bg-muted p-4 rounded-md text-sm text-destructive font-mono overflow-auto">
                {queryResult.error}
              </pre>
            </div>
          ) : (
            <div>
              <h3 className="font-semibold mb-2">Database Query Result:</h3>
              <div className="bg-muted p-4 rounded-md text-sm font-mono overflow-auto">
                 <p>Found <strong>{queryResult.count ?? 0}</strong> item(s) in the 'inventory' table for your company.</p>
              </div>
            </div>
          )}
        </CardContent>
        <CardFooter className="bg-muted/50 p-4 rounded-b-lg">
            <div className="flex items-start gap-3">
                 <Database className="h-5 w-5 text-muted-foreground mt-1"/>
                 <div>
                    <h4 className="font-semibold">What does this mean?</h4>
                    <p className="text-sm text-muted-foreground">If the query test is successful but you see no data on your dashboard, it likely means your database tables (like inventory, suppliers, etc.) are empty for your Company ID. You can add data directly in Supabase or use the "Import Data" page.</p>
                 </div>
            </div>
        </CardFooter>
      </Card>
    </div>
  );
}
