
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export default function Home() {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-muted/40">
      <Card className="w-full max-w-md text-center p-4">
        <CardHeader>
          <CardTitle className="text-3xl font-bold">Welcome to InvoChat</CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          <p className="text-muted-foreground">
            This is a temporary landing page for debugging purposes.
          </p>
          <div className="flex justify-center gap-4">
            <Button asChild>
              <Link href="/login">
                Go to Login
              </Link>
            </Button>
            <Button variant="secondary" asChild>
              <Link href="/dashboard">
                Go to Dashboard
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
