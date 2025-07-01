
'use client';

import { useState, useTransition } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { useToast } from '@/hooks/use-toast';

interface AmazonConnectModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const formSchema = z.object({
  sellerId: z.string().min(1, { message: 'Seller ID cannot be empty.' }),
  authToken: z.string().min(1, { message: 'MWS Auth Token cannot be empty.' }),
});

type FormData = z.infer<typeof formSchema>;

export function AmazonConnectModal({ isOpen, onClose }: AmazonConnectModalProps) {
    const { toast } = useToast();
    const [isPending, startTransition] = useTransition();
    const [error, setError] = useState<string | null>(null);

    const form = useForm<FormData>({
        resolver: zodResolver(formSchema),
        defaultValues: { sellerId: '', authToken: '' },
    });

    const onSubmit = (values: FormData) => {
        setError(null);
        startTransition(async () => {
            const response = await fetch('/api/amazon_fba/connect', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(values),
            });

            const result = await response.json();

            if (response.ok) {
                toast({ title: 'Success!', description: 'Your Amazon FBA account has been connected.' });
                onClose();
                window.location.reload();
            } else {
                setError(result.error || 'An unknown error occurred.');
            }
        });
    };

    return (
        <Dialog open={isOpen} onOpenChange={onClose}>
            <DialogContent className="sm:max-w-[600px]">
                <DialogHeader>
                    <DialogTitle>Connect Your Amazon FBA Account</DialogTitle>
                    <DialogDescription>
                        Enter your Seller ID and MWS Auth Token to connect.
                    </DialogDescription>
                </DialogHeader>
                <div className="py-4 space-y-4">
                    <Alert>
                        <AlertTitle>How to get your credentials</AlertTitle>
                        <AlertDescription className="space-y-1 text-xs">
                           <p>1. In Amazon Seller Central, go to: <strong>Settings → User Permissions</strong>.</p>
                           <p>2. Under "Third-party developer and apps", click "Visit Manage Your Apps".</p>
                           <p>3. Authorize a new developer with Developer ID: [Our ID] and Name: InvoChat.</p>
                           <p>4. This will provide you with your Seller ID and an MWS Authorization Token.</p>
                        </AlertDescription>
                    </Alert>
                    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
                        <div className="space-y-2">
                            <Label htmlFor="sellerId">Seller ID</Label>
                            <Input id="sellerId" placeholder="e.g., A1234567890XYZ" {...form.register('sellerId')} />
                            {form.formState.errors.sellerId && <p className="text-sm text-destructive">{form.formState.errors.sellerId.message}</p>}
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="authToken">MWS Auth Token</Label>
                            <Input id="authToken" type="password" placeholder="amzn.mws.xxxx-xxxx-xxxx" {...form.register('authToken')} />
                            {form.formState.errors.authToken && <p className="text-sm text-destructive">{form.formState.errors.authToken.message}</p>}
                        </div>
                        {error && <p className="text-sm text-destructive">{error}</p>}
                        <DialogFooter>
                            <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
                            <Button type="submit" disabled={isPending} className="bg-[#FF9900] hover:bg-[#E68A00] text-white">
                                {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                Test & Connect
                            </Button>
                        </DialogFooter>
                    </form>
                </div>
            </DialogContent>
        </Dialog>
    );
}
