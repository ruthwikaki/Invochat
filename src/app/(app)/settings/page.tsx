
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
import { SidebarTrigger } from '@/components/ui/sidebar';
import { useToast } from '@/hooks/use-toast';
import type { CompanySettings } from '@/types';
import { getCompanySettings, updateCompanySettings } from '@/app/data-actions';
import { Skeleton } from '@/components/ui/skeleton';
import { Settings as SettingsIcon, Users, Palette, Briefcase, Image as ImageIcon, Info } from 'lucide-react';
import Link from 'next/link';

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
        <div className="p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <h1 className="text-2xl font-semibold">Settings</h1>
                </div>
            </div>
            
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
        </div>
    );
}
