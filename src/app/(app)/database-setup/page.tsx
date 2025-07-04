
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
import { Alert, AlertDescription } from '@/components/ui/alert';

const sqlCode = SETUP_SQL_SCRIPT;

export default function DatabaseSetupPage() {
    const { toast } = useToast();
    const [encryptionKey, setEncryptionKey] = useState('');
    const [encryptionIv, setEncryptionIv] = useState('');

    const copyToClipboard = (text: string, successMessage: string) => {
        if (!text) return;
        if (typeof navigator === 'undefined' || !navigator.clipboard) {
            toast({
                variant: 'destructive',
                title: 'Clipboard API Not Available',
                description: 'Could not copy to clipboard. Please copy the text manually.',
            });
            return;
        }
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
        if (typeof window === 'undefined' || !window.crypto || !window.crypto.getRandomValues) {
            toast({
                variant: 'destructive',
                title: 'Crypto API Not Available',
                description: 'Could not generate keys in this browser. Please use a modern browser or a secure connection (HTTPS).',
            });
            return;
        }
        const key = new Uint8Array(32);
        const iv = new Uint8Array(16);
        window.crypto.getRandomValues(key);
        window.crypto.getRandomValues(iv);

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
            title="Initial Deployment Setup"
            description="This page is for the initial deployment administrator. The script below configures the database for multi-tenancy. Your clients will have their companies created automatically upon signup and will never see this page."
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
                        2. Generate & Add Encryption Keys
                    </CardTitle>
                    <CardDescription>
                       The app needs two secret keys in your `.env` file to securely handle API credentials. Since `openssl` is not available on your system, you can use this secure, in-browser generator.
                    </CardDescription>
                </CardHeader>
                <CardContent className="space-y-6">
                    <div className="space-y-2">
                        <h4 className="font-semibold">Step 1: Generate the Keys</h4>
                        <p className="text-sm text-muted-foreground">Click the button below. The keys are generated only in your browser and are never sent to a server.</p>
                        <Button onClick={generateKeys} type="button">
                            <Wand2 className="mr-2 h-4 w-4"/>
                            Generate Secure Keys
                        </Button>
                    </div>

                    <div className="space-y-4">
                        <h4 className="font-semibold">Step 2: Copy the Keys</h4>
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

                    <div className="space-y-2">
                        <h4 className="font-semibold">Step 3: Add Keys to your `.env` file</h4>
                        <p className="text-sm text-muted-foreground">Open the `.env` file in the root of your project and paste the keys in this format:</p>
                        <Alert className="font-mono text-xs">
                           <AlertDescription>
                            ENCRYPTION_KEY={encryptionKey || 'your_generated_64_character_key_here'}<br/>
                            ENCRYPTION_IV={encryptionIv || 'your_generated_32_character_key_here'}
                           </AlertDescription>
                        </Alert>
                    </div>
                </CardContent>
                 <CardFooter>
                    <p className="text-sm text-muted-foreground font-semibold">
                        After adding the keys, restart the application for the changes to take effect.
                    </p>
                </CardFooter>
            </Card>
        </div>
    </AppPage>
  );
}
