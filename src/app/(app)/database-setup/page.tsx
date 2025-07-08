
'use client';

import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { ClipboardCopy, AlertTriangle, LogOut } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { SETUP_SQL_SCRIPT } from '@/lib/database-schema';
import { useRouter } from 'next/navigation';

export default function DatabaseSetupPage() {
    const { toast } = useToast();
    const router = useRouter();

    const copyToClipboard = () => {
        navigator.clipboard.writeText(SETUP_SQL_SCRIPT).then(() => {
            toast({
                title: 'Copied to Clipboard!',
                description: 'You can now paste this into the Supabase SQL Editor.',
            });
        }, (err) => {
            toast({
                variant: 'destructive',
                title: 'Failed to Copy',
                description: 'Could not copy code to clipboard. Please copy it manually.',
            });
        });
    };

    const handleSignOut = () => {
        // A proper sign-out should ideally be a server action, but for this page,
        // a simple redirect is sufficient to get the user back to the login flow.
        router.push('/login');
    };

    return (
        <AppPage>
            <AppPageHeader
                title="Database Setup"
                description="Use this script to initialize a new database."
            />
            <Card>
                <CardContent className="pt-6">
                    <ol className="list-decimal list-inside space-y-4 text-base">
                        <li>
                            <strong className="font-semibold">Copy the SQL Script:</strong> Click the button below to copy the entire setup script to your clipboard.
                        </li>
                        <li>
                            <strong className="font-semibold">Run in Supabase:</strong> Navigate to the <a href="https://supabase.com/dashboard" target="_blank" rel="noopener noreferrer" className="text-primary underline">Supabase Dashboard</a>, select your project, go to the <strong className="font-semibold">SQL Editor</strong>, paste the copied code, and click <strong className="font-semibold">"Run"</strong>.
                        </li>
                        <li>
                            <div className="rounded-md border border-warning/50 bg-warning/10 p-4 mt-2">
                                <div className="flex items-start gap-3">
                                    <AlertTriangle className="h-5 w-5 text-warning shrink-0 mt-1" />
                                    <div>
                                        <h4 className="font-semibold text-warning">Important Final Step</h4>
                                        <p className="text-sm text-warning/80">
                                            After running the script, you <strong className="font-semibold">must sign out and sign up with a new user account</strong>. The script you just ran creates a trigger that properly links new users to a company. Your old user account will not be linked correctly.
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </li>
                    </ol>

                     <div className="flex justify-center gap-4 mt-6">
                        <Button size="lg" onClick={copyToClipboard}>
                            <ClipboardCopy className="mr-2 h-4 w-4" /> Copy SQL Script
                        </Button>
                         <Button size="lg" variant="outline" onClick={handleSignOut}>
                            <LogOut className="mr-2 h-4 w-4" /> Sign Out
                        </Button>
                    </div>

                    <div className="mt-8">
                        <h3 className="text-lg font-semibold mb-2">Full SQL Script Preview</h3>
                        <div className="max-h-96 overflow-y-auto rounded-md border bg-muted p-4">
                            <pre className="text-xs font-mono whitespace-pre-wrap">
                                <code>{SETUP_SQL_SCRIPT}</code>
                            </pre>
                        </div>
                    </div>
                </CardContent>
            </Card>
        </AppPage>
    );
}
