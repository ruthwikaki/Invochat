
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
import { useQueryClient } from '@tanstack/react-query';

interface WooCommerceConnectModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const formSchema = z.object({
  storeUrl: z.string().url({ message: 'Must be a valid URL, e.g., https://your-store.com' }),
  consumerKey: z.string().startsWith('ck_', { message: 'Key must start with "ck_"' }),
  consumerSecret: z.string().startsWith('cs_', { message: 'Secret must start with "cs_"' }),
});

type FormData = z.infer<typeof formSchema>;

export function WooCommerceConnectModal({ isOpen, onClose }: WooCommerceConnectModalProps) {
    const { toast } = useToast();
    const queryClient = useQueryClient();
    const [isPending, startTransition] = useTransition();
    const [error, setError] = useState<string | null>(null);

    const form = useForm<FormData>({
        resolver: zodResolver(formSchema),
        defaultValues: { storeUrl: '', consumerKey: '', consumerSecret: '' },
    });

    const onSubmit = (values: FormData) => {
        setError(null);
        startTransition(async () => {
            const response = await fetch('/api/woocommerce/connect', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(values),
            });

            const result = await response.json();

            if (response.ok) {
                toast({ title: 'Success!', description: 'Your WooCommerce store has been connected.' });
                await queryClient.invalidateQueries({ queryKey: ['integrations'] });
                onClose();
            } else {
                setError(result.error || 'An unknown error occurred.');
            }
        });
    };

    return (
        <Dialog open={isOpen} onOpenChange={onClose}>
            <DialogContent className="sm:max-w-[600px]">
                <DialogHeader>
                    <DialogTitle>Connect Your WooCommerce Store</DialogTitle>
                    <DialogDescription>
                        Enter your store URL and REST API keys to connect.
                    </DialogDescription>
                </DialogHeader>
                <div className="py-4 space-y-4">
                     <Alert>
                        <AlertTitle>How to get your credentials</AlertTitle>
                        <AlertDescription className="space-y-1 text-xs">
                           <p>1. In your WordPress Admin, go to: <strong>WooCommerce → Settings → Advanced → REST API</strong>.</p>
                           <p>2. Click "Add key" to create new API keys.</p>
                           <p>3. Give the key a description (e.g., "InvoChat Integration") and set Permissions to "Read/Write".</p>
                           <p>4. Click "Generate API key" and copy the Consumer Key and Consumer Secret provided.</p>
                        </AlertDescription>
                    </Alert>
                    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
                        <div className="space-y-2">
                            <Label htmlFor="storeUrl">Store URL</Label>
                            <Input id="storeUrl" placeholder="https://your-store.com" {...form.register('storeUrl')} />
                            {form.formState.errors.storeUrl && <p className="text-sm text-destructive">{form.formState.errors.storeUrl.message}</p>}
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="consumerKey">Consumer Key</Label>
                            <Input id="consumerKey" placeholder="ck_..." {...form.register('consumerKey')} />
                             {form.formState.errors.consumerKey && <p className="text-sm text-destructive">{form.formState.errors.consumerKey.message}</p>}
                        </div>
                         <div className="space-y-2">
                            <Label htmlFor="consumerSecret">Consumer Secret</Label>
                            <Input id="consumerSecret" type="password" placeholder="cs_..." {...form.register('consumerSecret')} />
                             {form.formState.errors.consumerSecret && <p className="text-sm text-destructive">{form.formState.errors.consumerSecret.message}</p>}
                        </div>
                        {error && <p className="text-sm text-destructive">{error}</p>}
                        <DialogFooter>
                            <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
                            <Button type="submit" disabled={isPending} className="bg-[#96588A] hover:bg-[#834b78] text-white">
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
