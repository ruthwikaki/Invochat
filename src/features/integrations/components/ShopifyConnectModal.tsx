
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
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';

interface ShopifyConnectModalProps {
  isOpen: boolean;
  onClose: () => void;
}

const formSchema = z.object({
  storeUrl: z.string().url({ message: 'Must be a valid URL, e.g., https://your-store.myshopify.com' }),
  accessToken: z.string().startsWith('shpat_', { message: 'Token must start with "shpat_"' }),
});

type FormData = z.infer<typeof formSchema>;

export function ShopifyConnectModal({ isOpen, onClose }: ShopifyConnectModalProps) {
    const { toast } = useToast();
    const { user } = useAuth();
    const [isPending, startTransition] = useTransition();
    const [error, setError] = useState<string | null>(null);

    const form = useForm<FormData>({
        resolver: zodResolver(formSchema),
        defaultValues: { storeUrl: '', accessToken: '' },
    });

    const onSubmit = (values: FormData) => {
        setError(null);
        startTransition(async () => {
            const payload = {
                ...values,
                companyId: user?.app_metadata?.company_id,
            };

            const response = await fetch('/api/shopify/connect', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });

            const result = await response.json();

            if (response.ok) {
                toast({ title: 'Success!', description: 'Your Shopify store has been connected.' });
                onClose();
                window.location.reload(); // Reload to show the new integration card
            } else {
                setError(result.error || 'An unknown error occurred.');
            }
        });
    };

    return (
        <Dialog open={isOpen} onOpenChange={onClose}>
            <DialogContent className="sm:max-w-[600px]">
                <DialogHeader>
                    <DialogTitle>Connect Your Shopify Store</DialogTitle>
                    <DialogDescription>
                        Enter your store URL and Admin API access token to connect.
                    </DialogDescription>
                </DialogHeader>
                <div className="py-4 space-y-4">
                    <Alert>
                        <AlertTitle>How to get your credentials</AlertTitle>
                        <AlertDescription className="space-y-1 text-xs">
                            <p>1. In your Shopify Admin, go to: <strong>Settings → Apps and sales channels → Develop apps</strong>.</p>
                            <p>2. Create a new app named "InvoChat Integration" and configure Admin API scopes.</p>
                            <p>3. Grant these permissions: <strong>read_products, read_orders, read_inventory, write_inventory</strong>.</p>
                            <p>4. Install the app and copy the <strong>Admin API access token</strong> shown.</p>
                        </AlertDescription>
                    </Alert>
                    <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
                        <div className="space-y-2">
                            <Label htmlFor="storeUrl">Shopify Store URL</Label>
                            <Input id="storeUrl" placeholder="https://your-store.myshopify.com" {...form.register('storeUrl')} />
                            {form.formState.errors.storeUrl && <p className="text-sm text-destructive">{form.formState.errors.storeUrl.message}</p>}
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="accessToken">Admin API Access Token</Label>
                            <Input id="accessToken" type="password" placeholder="shpat_..." {...form.register('accessToken')} />
                             {form.formState.errors.accessToken && <p className="text-sm text-destructive">{form.formState.errors.accessToken.message}</p>}
                        </div>
                        {error && <p className="text-sm text-destructive">{error}</p>}
                        <DialogFooter>
                            <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
                            <Button type="submit" disabled={isPending} className="bg-[#78AB43] hover:bg-[#699939] text-white">
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
