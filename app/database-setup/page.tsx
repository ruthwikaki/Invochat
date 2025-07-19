
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import Link from 'next/link';
import { Button } from '@/components/ui/button';

export default function DatabaseSetupPage() {

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
        <Card className="w-full max-w-2xl">
        <CardHeader>
            <div className="mx-auto bg-primary/10 p-3 rounded-full w-fit mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="h-8 w-8 text-primary"><path d="M12 2L2 7l10 5 10-5-10-5z"></path><path d="M2 17l10 5 10-5"></path><path d="M2 12l10 5 10-5"></path></svg>
            </div>
            <CardTitle className="text-center text-2xl">Final Database Setup Step</CardTitle>
            <CardDescription className="text-center">
            To get your app running, the database needs to be configured correctly.
            </CardDescription>
        </CardHeader>
        <CardContent className="text-center space-y-4">
            <p className="text-sm text-muted-foreground">
                Please ensure your Supabase project has been set up according to the project's documentation. This includes creating the necessary tables, functions, and security policies for ARVO to work correctly.
            </p>
             <p className="text-sm text-muted-foreground">
                After the setup is complete, you can sign up for a new account. If you already signed up, you must create a new account to ensure it's configured correctly.
            </p>
        </CardContent>
        <CardFooter className="flex-col gap-4">
             <Button asChild className="w-full">
                <Link href="/signup">Go to Sign Up Page</Link>
            </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
