
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { AlertTriangle, CheckCircle, Server } from "lucide-react";

export default function EnvCheckPage() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || 'NOT SET';
  const googleApiKey = process.env.GOOGLE_API_KEY;
  const isGoogleKeySet = googleApiKey && googleApiKey.length > 10;

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-muted/40 p-4">
      <Card className="w-full max-w-2xl">
        <CardHeader>
          <div className="mx-auto bg-primary/10 p-3 rounded-full w-fit mb-4">
            <Server className="h-8 w-8 text-primary" />
          </div>
          <CardTitle className="text-center text-2xl">Environment Variable Check</CardTitle>
          <CardDescription className="text-center">
            This page shows the environment variables your Next.js server is currently using. This helps confirm if your <code>.env</code> file changes have been applied.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <h3 className="font-semibold">Supabase URL:</h3>
            <div className="bg-muted p-3 rounded-md font-mono text-sm break-all">
              {supabaseUrl}
            </div>
            <p className="text-xs text-muted-foreground">
              Compare this URL to the one in your new Supabase project's API settings. If it's wrong, it means your server is still using old, cached values.
            </p>
          </div>

          <div className="space-y-2">
            <h3 className="font-semibold">Google API Key Status:</h3>
            <div className="flex items-center gap-2 bg-muted p-3 rounded-md text-sm">
              {isGoogleKeySet ? (
                <CheckCircle className="h-5 w-5 text-success" />
              ) : (
                <AlertTriangle className="h-5 w-5 text-destructive" />
              )}
              <span>{isGoogleKeySet ? 'GOOGLE_API_KEY is set.' : 'GOOGLE_API_KEY is NOT set.'}</span>
            </div>
          </div>

          <div className="border-t pt-4 mt-4">
            <h3 className="font-semibold text-destructive mb-2">If these values are incorrect:</h3>
            <ol className="list-decimal list-inside space-y-2 text-sm">
              <li>Make sure your <code>.env</code> file is saved in the root directory of the project.</li>
              <li>Double-check that the variable names (e.g., <code>NEXT_PUBLIC_SUPABASE_URL</code>) are spelled correctly.</li>
              <li>
                <strong>Force a full server restart.</strong> Stop the running process completely (<code>Ctrl+C</code> in your terminal) and start it again with <code>npm run dev</code>. This usually fixes caching issues.
              </li>
            </ol>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
