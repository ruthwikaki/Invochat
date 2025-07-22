'use client';

import { useState, useEffect } from 'react';
import { createBrowserClient } from '@supabase/ssr';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export default function SupabaseTestPage() {
  const [connectionStatus, setConnectionStatus] = useState<'checking' | 'connected' | 'error'>('checking');
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [userCount, setUserCount] = useState<number | null>(null);

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  useEffect(() => {
    testConnection();
  }, []);

  const testConnection = async () => {
    try {
      setConnectionStatus('checking');
      
      // Test basic connection
      const { data, error, count } = await supabase.from('auth.users').select('*', { count: 'exact', head: true });
      
      if (error) {
        throw error;
      }

      setConnectionStatus('connected');
      setUserCount(count);
    } catch (error: any) {
      setConnectionStatus('error');
      setErrorMessage(error.message || 'Unknown error occurred');
    }
  };

  const testSignUp = async () => {
    try {
      const testEmail = `test-${Date.now()}@example.com`;
      const { data, error } = await supabase.auth.signUp({
        email: testEmail,
        password: 'testpassword123',
        options: {
          data: {
            company_name: 'Test Company',
            company_id: crypto.randomUUID(),
          }
        }
      });

      if (error) {
        alert(`Signup Error: ${error.message}`);
      } else {
        alert(`Signup successful! User ID: ${data.user?.id}`);
      }
    } catch (error: any) {
      alert(`Signup failed: ${error.message}`);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Supabase Connection Test</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div>
            <strong>Status:</strong>{' '}
            <span className={
              connectionStatus === 'connected' ? 'text-green-600' :
              connectionStatus === 'error' ? 'text-red-600' :
              'text-yellow-600'
            }>
              {connectionStatus === 'checking' && 'Checking connection...'}
              {connectionStatus === 'connected' && 'Connected ✓'}
              {connectionStatus === 'error' && 'Connection failed ✗'}
            </span>
          </div>

          {connectionStatus === 'error' && (
            <div className="text-red-600 text-sm">
              <strong>Error:</strong> {errorMessage}
            </div>
          )}

          {connectionStatus === 'connected' && userCount !== null && (
            <div className="text-green-600 text-sm">
              <strong>Users in database:</strong> {userCount}
            </div>
          )}

          <div className="space-y-2">
            <Button onClick={testConnection} className="w-full" variant="outline">
              Test Connection Again
            </Button>
            <Button onClick={testSignUp} className="w-full" variant="outline">
              Test Signup
            </Button>
          </div>

          <div className="text-xs text-muted-foreground">
            <p><strong>Supabase URL:</strong> {process.env.NEXT_PUBLIC_SUPABASE_URL}</p>
            <p><strong>Anon Key:</strong> {process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.substring(0, 20)}...</p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}