
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
import { Settings as SettingsIcon, Users, Palette, Briefcase, Image as ImageIcon, Info, Loader2, DollarSign, Percent, Save } from 'lucide-react';
import Link from 'next/link';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

const businessRulesFields: { key: keyof CompanySettings; label: string; description: string, type: string }[] = [
    { key: 'dead_stock_days', label: 'Dead Stock Threshold (Days)', description: 'Days an item must be unsold to be "dead stock".', type: 'number' },
    { key: 'fast_moving_days', label: 'Fast-Moving Item Window (Days)', description: 'Timeframe to consider for "fast-moving" items.', type: 'number' },
    { key: 'overstock_multiplier', label: 'Overstock Multiplier', description: 'Reorder point is multiplied by this to define "overstock".', type: 'number' },
    { key: 'high_value_threshold', label: 'High-Value Threshold ($)', description: 'The cost above which an item is considered "high-value".', type: 'number' },
];

const generalSettingsFields: { key: keyof CompanySettings; label: string; description: string, type: string, placeholder: string }[] = [
    { key: 'currency', label: 'Currency Code', description: 'e.g., USD, EUR. Used for formatting.', type: 'text', placeholder: 'USD' },
    { key: 'timezone', label: 'Timezone', description: 'e.g., UTC, America/New_York. Used for date display.', type: 'text', placeholder: 'UTC' },
    { key: 'tax_rate', label: 'Default Tax Rate (%)', description: 'Default sales tax rate for calculations.', type: 'number', placeholder: '8.5' },
];

const themeFields: { key: keyof CompanySettings; label: string; description: string }[] = [
    { key: 'theme_primary_color', label: 'Primary Color', description: 'Main color for buttons and highlights.' },
    { key: 'theme_background_color', label: 'Background Color', description: 'Main page background color.' },
    { key: 'theme_accent_color', label: 'Accent Color', description: 'Color for secondary elements and hovers.' },
];

function ChannelFeeManager() {
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
                    <Button type="submit" disabled={isPending} className="w-full">
                        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        Save Channel Fee
                    </Button>
                 </form>
            </div>
        </div>
    );
}


export default function SettingsPage() {
    const [settings, setSettings] = useState<Partial<CompanySettings>>({});
    const [loading, setLoading] = useState(true);
    const [isPending, startTransition] = useTransition();
    const { toast } = useToast();

    useEffect(() => {
        async function fetchSettings() {
            setLoading(true);
            try {
                const currentSettings = await getCompanySettings();
                setSettings(currentSettings);
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
    }, [toast]);
    
    const handleInputChange = (key: keyof CompanySettings, value: string) => {
        const fieldType = [...generalSettingsFields, ...businessRulesFields, ...themeFields].find(f => f.key === key)?.type;
        const processedValue = fieldType === 'number' && value !== '' ? Number(value) : value;
        setSettings(prev => ({ ...prev, [key]: processedValue }));
    };

    const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        startTransition(async () => {
            try {
                // Ensure numeric values are numbers before sending
                const settingsToUpdate = { ...settings };
                [...businessRulesFields, ...generalSettingsFields].forEach(field => {
                    const fieldDef = [...businessRulesFields, ...generalSettingsFields].find(f => f.key === field.key);
                    if (fieldDef?.type === 'number' && typeof settingsToUpdate[field.key] !== 'number') {
                         settingsToUpdate[field.key] = Number(settingsToUpdate[field.key]) || 0;
                    }
                });
                
                await updateCompanySettings(settingsToUpdate as CompanySettings);

                toast({
                    title: 'Success',
                    description: 'Your settings have been updated. Refreshing to apply changes...',
                });
                
                setTimeout(() => window.location.reload(), 1500);

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
            
            <form onSubmit={handleSubmit} className="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
                <div className="lg:col-span-2 space-y-6">
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

                     {/* Channel Fees Card */}
                    <Card>
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
                            <ChannelFeeManager />
                        </CardContent>
                    </Card>


                    {/* Theming Card */}
                     <Card>
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <Palette className="h-5 w-5" />
                                Branding & Theming
                            </CardTitle>
                            <CardDescription>
                                Customize the look and feel of your workspace. Use HSL format for colors.
                            </CardDescription>
                        </CardHeader>
                        <CardContent>
                            {loading ? <Skeleton className="h-64 w-full" /> : (
                                <div className="space-y-6">
                                    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                                        {themeFields.map(({ key, label, description }) => (
                                            <div key={key} className="space-y-2">
                                                <Label htmlFor={key}>{label}</Label>
                                                <Input
                                                    id={key}
                                                    type="text"
                                                    value={settings[key] as string || ''}
                                                    onChange={(e) => handleInputChange(key, e.target.value)}
                                                    placeholder='e.g., 262 84% 59%'
                                                />
                                                <p className="text-xs text-muted-foreground">{description}</p>
                                            </div>
                                        ))}
                                    </div>
                                    <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted p-2 rounded-lg">
                                        <Info className="h-4 w-4 shrink-0" />
                                        <span>You can get HSL color values from web tools like <a href="https://hslpicker.com/" target="_blank" rel="noopener noreferrer" className="underline">hslpicker.com</a>.</span>
                                    </div>
                                </div>
                            )}
                        </CardContent>
                    </Card>

                    <div className="flex justify-end pt-4">
                        <Button type="submit" disabled={isPending || loading} size="lg">
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            {isPending ? 'Saving...' : 'Save All Settings'}
                        </Button>
                    </div>
                </div>

                <div className="space-y-6 lg:col-span-1">
                     {/* General Settings Card */}
                    <Card>
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <Briefcase className="h-5 w-5" />
                                General
                            </CardTitle>
                             <CardDescription>
                                Company-wide localization and financial settings.
                            </CardDescription>
                        </CardHeader>
                        <CardContent>
                             {loading ? <Skeleton className="h-48 w-full" /> : (
                                <div className="space-y-6">
                                    {generalSettingsFields.map(({ key, label, description, type, placeholder }) => (
                                        <div key={key} className="space-y-2">
                                            <Label htmlFor={key}>{label}</Label>
                                            <Input
                                                id={key}
                                                type={type}
                                                value={settings[key] as any || ''}
                                                onChange={(e) => handleInputChange(key, e.target.value)}
                                                placeholder={placeholder}
                                            />
                                            <p className="text-xs text-muted-foreground">{description}</p>
                                        </div>
                                    ))}
                                </div>
                            )}
                        </CardContent>
                    </Card>

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
                </div>
            </form>
        </AppPage>
    );
}
