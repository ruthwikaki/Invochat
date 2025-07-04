
'use client';

import { useState } from 'react';
import { useToast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { DatabaseZap, Copy, Shield, KeyRound, Wand2 } from 'lucide-react';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { SETUP_SQL_SCRIPT } from '@/lib/database-schema';
import { Label } from '@/components/ui/label';
import { Input } from '@/components/ui/input';

const sqlCode = SETUP_SQL_SCRIPT;

export default function DatabaseSetupPage() {
    const { toast } = useToast();
    const [encryptionKey, setEncryptionKey] = useState('');
    const [encryptionIv, setEncryptionIv] = useState('');

    const copyToClipboard = (text: string, successMessage: string) => {
        if (!text) return;
        navigator.clipboard.writeText(text).then(() => {
            toast({
                title: 'Copied to Clipboard!',
                description: successMessage,
            });
        }, (err) => {
            toast({
                variant: 'destructive',
                title: 'Failed to Copy',
                description: 'Could not copy code to clipboard. Please copy it manually.',
            });
            console.error('Could not copy text: ', err);
        });
    };
    
    const generateKeys = () => {
        const key = new Uint8Array(32);
        const iv = new Uint8Array(16);
        crypto.getRandomValues(key);
        crypto.getRandomValues(iv);

        const keyHex = Array.from(key).map(b => b.toString(16).padStart(2, '0')).join('');
        const ivHex = Array.from(iv).map(b => b.toString(16).padStart(2, '0')).join('');
        
        setEncryptionKey(keyHex);
        setEncryptionIv(ivHex);

        toast({
            title: 'Keys Generated!',
            description: 'You can now copy these keys to your .env file.'
        });
    };

  return (
    <AppPage>
        <AppPageHeader
            title="Initial Setup"
            description="Run the database script and generate your encryption keys to complete setup."
        />
        <div className="space-y-8">
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <DatabaseZap className="h-6 w-6 text-primary"/>
                        1. Database Setup Script
                    </CardTitle>
                    <CardDescription>
                        This script contains all tables and functions needed for the application. It is safe to run multiple times. Paste this into your Supabase SQL Editor and click "Run".
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <div className="max-h-[40vh] overflow-y-auto rounded-md border bg-muted p-4">
                        <pre className="text-xs font-mono whitespace-pre-wrap">
                            <code>{sqlCode}</code>
                        </pre>
                    </div>
                </CardContent>
                <CardFooter>
                    <Button onClick={() => copyToClipboard(sqlCode, 'SQL script copied to clipboard.')} className="w-full md:w-auto">
                        <Copy className="mr-2 h-4 w-4" />
                        Copy SQL to Clipboard
                    </Button>
                </CardFooter>
            </Card>

             <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <Shield className="h-6 w-6 text-primary"/>
                        2. Generate Encryption Keys
                    </CardTitle>
                    <CardDescription>
                       If you don't have OpenSSL, you can use this to generate the secure keys required for your `.env` file. These keys are generated only in your browser.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-6">
                    <Button onClick={generateKeys} type="button">
                        <Wand2 className="mr-2 h-4 w-4"/>
                        Generate Secure Keys
                    </Button>
                    <div className="space-y-4">
                        <div className="space-y-2">
                            <Label htmlFor="encryptionKey">ENCRYPTION_KEY (64 characters)</Label>
                             <div className="flex w-full items-center space-x-2">
                                <Input id="encryptionKey" value={encryptionKey} readOnly placeholder="Click generate to create key..."/>
                                <Button type="button" variant="secondary" onClick={() => copyToClipboard(encryptionKey, 'Encryption Key copied to clipboard.')} disabled={!encryptionKey}>
                                    <Copy className="h-4 w-4" />
                                </Button>
                             </div>
                        </div>
                         <div className="space-y-2">
                            <Label htmlFor="encryptionIv">ENCRYPTION_IV (32 characters)</Label>
                            <div className="flex w-full items-center space-x-2">
                                <Input id="encryptionIv" value={encryptionIv} readOnly placeholder="Click generate to create IV..."/>
                                <Button type="button" variant="secondary" onClick={() => copyToClipboard(encryptionIv, 'Encryption IV copied to clipboard.')} disabled={!encryptionIv}>
                                    <Copy className="h-4 w-4" />
                                </Button>
                             </div>
                        </div>
                    </div>
                </CardContent>
                 <CardFooter>
                    <p className="text-xs text-muted-foreground">
                        After generating, copy these values into your `.env` file and restart the application.
                    </p>
                </CardFooter>
            </Card>
        </div>
    </AppPage>
  );
}

