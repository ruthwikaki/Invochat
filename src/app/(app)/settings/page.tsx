
'use client';

import { useState, useEffect, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import type { CompanySettings, ChannelFee } from '@/types';
import { getCompanySettings, updateCompanySettings, getChannelFees, upsertChannelFee } from '@/app/data-actions';
import { Skeleton } from '@/components/ui/skeleton';
import { Settings as SettingsIcon, Users, Palette, Briefcase, Image as ImageIcon, Info, Loader2, DollarSign, Percent, Save, CreditCard, Download, Undo2 } from 'lucide-react';
import Link from 'next/link';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';

function getCookie(name: string): string | null {
  if (typeof document === 'undefined') return null;
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop()?.split(';').shift() || null;
  return null;
}

const businessRulesFields: { key: keyof CompanySettings; label: string; description: string, type: string }[] = [
    { key: 'dead_stock_days', label: 'Dead Stock Threshold (Days)', description: 'Days an item must be unsold to be "dead stock".', type: 'number' },
    { key: 'fast_moving_days', label: 'Fast-Moving Item Window (Days)', description: 'Timeframe to consider for "fast-moving" items.', type: 'number' },
    { key: 'overstock_multiplier', label: 'Overstock Multiplier', description: 'Reorder point is multiplied by this to define "overstock".', type: 'number' },
    { key: 'high_value_threshold', label: 'High-Value Threshold ($)', description: 'The cost above which an item is considered "high-value".', type: 'number' },
];

function ChannelFeeManager({ csrfToken }: { csrfToken: string | null }) {
    const [fees, setFees] = useState<ChannelFee[]>([]);
    const [loading, setLoading] = useState(true);
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();

    useEffect(() => {
        getChannelFees().then(setFees).finally(() => setLoading(false));
    }, []);

    const handleFeeSubmit = async (formData: FormData) => {
        startTransition(async () => {
            const result = await upsertChannelFee(formData);
            if (result.success) {
                toast({ title: 'Success', description: 'Channel fee saved successfully.' });
                // Refetch fees to update the list
                getChannelFees().then(setFees);
            } else {
                toast({ variant: 'destructive', title: 'Error', description: result.error });
            }
        });
    };

    if (loading) {
        return <Skeleton className="h-48 w-full" />;
    }

    return (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
            <div>
                <h4 className="font-semibold mb-2">Current Fees</h4>
                <div className="rounded-md border">
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>Channel</TableHead>
                                <TableHead className="text-right">% Fee</TableHead>
                                <TableHead className="text-right">Fixed Fee</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {fees.length > 0 ? fees.map(fee => (
                                <TableRow key={fee.id}>
                                    <TableCell className="font-medium">{fee.channel_name}</TableCell>
                                    <TableCell className="text-right">{(fee.percentage_fee * 100).toFixed(2)}%</TableCell>
                                    <TableCell className="text-right">${fee.fixed_fee.toFixed(2)}</TableCell>
                                </TableRow>
                            )) : (
                                <TableRow>
                                    <TableCell colSpan={3} className="text-center text-muted-foreground">No channel fees configured.</TableCell>
                                </TableRow>
                            )}
                        </TableBody>
                    </Table>
                </div>
            </div>
            <div>
                 <h4 className="font-semibold mb-2">Add or Update Fee</h4>
                 <form action={handleFeeSubmit} className="space-y-4 rounded-md border p-4">
                    <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken || ''} />
                    <div className="space-y-2">
                        <Label htmlFor="channel_name">Channel Name</Label>
                        <Input name="channel_name" id="channel_name" placeholder="e.g., Shopify" required />
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="percentage_fee">Percentage Fee</Label>
                        <div className="relative">
                            <Input name="percentage_fee" id="percentage_fee" type="number" step="0.0001" placeholder="e.g., 0.029 for 2.9%" required />
                             <Percent className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                        </div>
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="fixed_fee">Fixed Fee</Label>
                         <div className="relative">
                            <Input name="fixed_fee" id="fixed_fee" type="number" step="0.01" placeholder="e.g., 0.30 for 30 cents" required />
                             <DollarSign className="absolute right-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                        </div>
                    </div>
                    <Button type="submit" disabled={isPending || !csrfToken} className="w-full">
                        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        Save Channel Fee
                    </Button>
                 </form>
            </div>
        </div>
    );
}


export default function SettingsPage() {
    const [initialSettings, setInitialSettings] = useState<Partial<CompanySettings>>({});
    const [settings, setSettings] = useState<Partial<CompanySettings>>({});
    const [loading, setLoading] = useState(true);
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();
    const [csrfToken, setCsrfToken] = useState<string | null>(null);

    // Fetch initial settings
    useEffect(() => {
        async function fetchSettings() {
            setLoading(true);
            try {
                const currentSettings = await getCompanySettings();
                setSettings(currentSettings);
                setInitialSettings(currentSettings);
            } catch (error) {
                toast({
                    variant: 'destructive',
                    title: 'Error',
                    description: 'Could not load company settings.',
                });
            } finally {
                setLoading(false);
            }
        }
        fetchSettings();
        setCsrfToken(getCookie('csrf_token'));
    }, [toast]);
    
    const handleInputChange = (key: keyof CompanySettings, value: string) => {
        const field = businessRulesFields.find(f => f.key === key);
        const processedValue = field?.type === 'number' && value !== '' ? Number(value) : value;
        setSettings(prev => ({ ...prev, [key]: processedValue }));
    };

    const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        startTransition(async () => {
            try {
                const formData = new FormData(e.currentTarget);
                await updateCompanySettings(formData);
                toast({
                    title: 'Success',
                    description: 'Your settings have been updated.',
                });
                setInitialSettings(settings); // Update the baseline for "Reset"
            } catch (error) {
                toast({
                    variant: 'destructive',
                    title: 'Error',
                    description: 'Failed to update settings.',
                });
            }
        });
    }

    return (
        <AppPage>
            <AppPageHeader title="Settings" />
            
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
                <div className="lg:col-span-2 space-y-6">
                    <form onSubmit={handleSubmit}>
                        <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken || ''} />
                        {/* Business Rules Card */}
                        <Card>
                            <CardHeader>
                                <CardTitle className="flex items-center gap-2">
                                    <SettingsIcon className="h-5 w-5" />
                                    Business Rules
                                </CardTitle>
                                <CardDescription>
                                    Define thresholds that affect reports, alerts, and AI responses.
                                </CardDescription>
                            </CardHeader>
                            <CardContent>
                                {loading ? <Skeleton className="h-48 w-full" /> : (
                                    <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                                        {businessRulesFields.map(({ key, label, description, type }) => (
                                            <div key={key} className="space-y-2">
                                                <Label htmlFor={key} className="text-base">{label}</Label>
                                                <Input
                                                    id={key}
                                                    name={key}
                                                    type={type}
                                                    value={settings[key] || ''}
                                                    onChange={(e) => handleInputChange(key, e.target.value)}
                                                    className="text-lg"
                                                />
                                                <p className="text-sm text-muted-foreground">{description}</p>
                                            </div>
                                        ))}
                                    </div>
                                )}
                            </CardContent>
                        </Card>

                         <div className="flex justify-end pt-4 mt-6">
                            <Button type="submit" disabled={isPending || loading || !csrfToken} size="lg">
                                {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                {isPending ? 'Saving...' : 'Save All Settings'}
                            </Button>
                        </div>
                    </form>

                     {/* Channel Fees Card */}
                    <Card className="mt-6">
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <DollarSign className="h-5 w-5" />
                                Sales Channel Fees
                            </CardTitle>
                            <CardDescription>
                                Configure fees for each sales channel to enable accurate Net Margin calculations.
                            </CardDescription>
                        </CardHeader>
                        <CardContent>
                            <ChannelFeeManager csrfToken={csrfToken} />
                        </CardContent>
                    </Card>
                </div>

                <div className="space-y-6 lg:col-span-1">
                     <Card>
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <Users className="h-5 w-5" />
                                Team Management
                            </CardTitle>
                            <CardDescription>Manage team members and access controls for your company.</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <p className="text-sm text-muted-foreground">
                                Invite your team to collaborate.
                            </p>
                        </CardContent>
                        <CardFooter>
                            <Button asChild variant="secondary" className="w-full">
                                <Link href="/settings/team">Manage Team</Link>
                            </Button>
                        </CardFooter>
                    </Card>

                     <Card>
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <CreditCard className="h-5 w-5" />
                                Billing & Subscription
                            </CardTitle>
                            <CardDescription>Manage your plan and view invoices.</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <p className="text-sm text-muted-foreground">
                                View your current plan and payment history.
                            </p>
                        </CardContent>
                        <CardFooter>
                            <Button asChild variant="secondary" className="w-full">
                                <Link href="/settings/billing">Manage Billing</Link>
                            </Button>
                        </CardFooter>
                    </Card>

                    <Card>
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <Download className="h-5 w-5" />
                                Data Export
                            </CardTitle>
                            <CardDescription>Request a full export of your company data.</CardDescription>
                        </CardHeader>
                        <CardContent>
                            <p className="text-sm text-muted-foreground">
                                Generate a CSV export of all your core business data.
                            </p>
                        </CardContent>
                        <CardFooter>
                            <Button asChild variant="secondary" className="w-full">
                                <Link href="/settings/export">Export Data</Link>
                            </Button>
                        </CardFooter>
                    </Card>

                </div>
            </div>
        </AppPage>
    );
}
