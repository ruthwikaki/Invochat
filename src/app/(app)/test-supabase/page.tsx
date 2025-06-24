
import { testSupabaseConnection } from '@/app/data-actions';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { AlertCircle, CheckCircle } from 'lucide-react';

export default async function TestSupabasePage() {
  const { success, error, user, isConfigured } = await testSupabaseConnection();

  return (
    <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center gap-2">
        <SidebarTrigger className="md:hidden" />
        <h1 className="text-2xl font-semibold">Supabase Connection Test</h1>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-3">
            {success ? <CheckCircle className="h-6 w-6 text-success" /> : <AlertCircle className="h-6 w-6 text-destructive" />}
            Connection Status
          </CardTitle>
          <CardDescription>
            This page tests the direct connection to your Supabase instance from the server.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center justify-between rounded-lg border p-3">
            <span className="font-medium">Credentials Configured</span>
             <Badge variant={isConfigured ? 'default' : 'destructive'}>
                {isConfigured ? 'Yes' : 'No'}
             </Badge>
          </div>
          
           <div className="flex items-center justify-between rounded-lg border p-3">
            <span className="font-medium">Connection Successful</span>
             <Badge variant={success ? 'default' : 'destructive'}>
                {success ? 'Yes' : 'No'}
             </Badge>
          </div>

          {error && (
            <div>
              <h3 className="font-semibold mb-2">Error Details:</h3>
              <pre className="bg-muted p-4 rounded-md text-sm text-destructive font-mono overflow-auto">
                {JSON.stringify(error, null, 2)}
              </pre>
            </div>
          )}
          
          {user && (
             <div>
              <h3 className="font-semibold mb-2">Authenticated User (from server):</h3>
              <div className="bg-muted p-4 rounded-md text-sm font-mono overflow-auto">
                <p><strong>ID:</strong> {user.id}</p>
                <p><strong>Email:</strong> {user.email}</p>
                <p><strong>Company ID:</strong> {user.app_metadata?.company_id || 'Not Found'}</p>
              </div>
            </div>
          )}

          {!user && success && (
             <div>
              <h3 className="font-semibold mb-2">Authenticated User:</h3>
              <p className="text-muted-foreground">No authenticated user session found on the server.</p>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
