
'use client';

import { useState, useEffect } from 'react';
import { createBrowserClient } from '@supabase/ssr';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';

export default function DebugLoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [connectionStatus, setConnectionStatus] = useState<'checking' | 'connected' | 'error'>('checking');

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
      
      // Test basic connection by checking auth state
      const { data: { session }, error } = await supabase.auth.getSession();
      
      if (error) {
        throw error;
      }

      setConnectionStatus('connected');
      setMessage(`Connection successful. Current session: ${session ? 'Active' : 'None'}`);
    } catch (error: any) {
      setConnectionStatus('error');
      setMessage(`Connection failed: ${error.message}`);
    }
  };

  const handleTestLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setMessage('');

    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) {
        setMessage(`Login failed: ${error.message}`);
      } else {
        setMessage(`Login successful! User ID: ${data.user?.id}, Email: ${data.user?.email}`);
        
        // Test redirect after delay
        setTimeout(() => {
          window.location.href = '/dashboard';
        }, 2000);
      }
    } catch (error: any) {
      setMessage(`Login error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleTestSignup = async () => {
    if (!email || !password) {
      setMessage('Please enter email and password first');
      return;
    }

    setLoading(true);
    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            company_name: 'Test Company',
            company_id: crypto.randomUUID(),
          }
        }
      });

      if (error) {
        setMessage(`Signup failed: ${error.message}`);
      } else {
        setMessage(`Signup successful! Check your email for confirmation. User ID: ${data.user?.id}`);
      }
    } catch (error: any) {
      setMessage(`Signup error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    try {
      const { error } = await supabase.auth.signOut();
      if (error) {
        setMessage(`Logout error: ${error.message}`);
      } else {
        setMessage('Logged out successfully');
        testConnection(); // Refresh connection status
      }
    } catch (error: any) {
      setMessage(`Logout error: ${error.message}`);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4 bg-gray-50">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Debug Login & Supabase Test</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Connection Status */}
          <Alert>
            <AlertDescription>
              <strong>Connection Status:</strong>{' '}
              <span className={
                connectionStatus === 'connected' ? 'text-green-600' :
                connectionStatus === 'error' ? 'text-red-600' :
                'text-yellow-600'
              }>
                {connectionStatus === 'checking' && 'Checking...'}
                {connectionStatus === 'connected' && 'Connected ✓'}
                {connectionStatus === 'error' && 'Failed ✗'}
              </span>
            </AlertDescription>
          </Alert>

          {/* Environment Info */}
          <div className="text-xs text-gray-500 space-y-1">
            <p><strong>Supabase URL:</strong> {process.env.NEXT_PUBLIC_SUPABASE_URL}</p>
            <p><strong>Anon Key:</strong> {process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY?.substring(0, 20)}...</p>
          </div>

          {/* Login Form */}
          <form onSubmit={handleTestLogin} className="space-y-4">
            <div>
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="test@example.com"
              />
            </div>
            <div>
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="password"
              />
            </div>
            
            <div className="space-y-2">
              <Button type="submit" className="w-full" disabled={loading}>
                {loading ? 'Testing...' : 'Test Login'}
              </Button>
              <Button type="button" onClick={handleTestSignup} className="w-full" variant="outline" disabled={loading}>
                Test Signup
              </Button>
              <Button type="button" onClick={handleLogout} className="w-full" variant="outline">
                Test Logout
              </Button>
              <Button type="button" onClick={testConnection} className="w-full" variant="outline">
                Test Connection
              </Button>
            </div>
          </form>

          {/* Message Display */}
          {message && (
            <Alert>
              <AlertDescription className="text-sm">
                {message}
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
