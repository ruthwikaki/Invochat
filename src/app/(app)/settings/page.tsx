
'use client';

import { useState, useEffect, useTransition } from 'react';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
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
import { Settings as SettingsIcon } from 'lucide-react';

const settingsFields: { key: keyof CompanySettings; label: string; description: string }[] = [
    { key: 'dead_stock_days', label: 'Dead Stock Threshold (Days)', description: 'Days an item must be unsold to be "dead stock".' },
    { key: 'fast_moving_days', label: 'Fast-Moving Item Window (Days)', description: 'Timeframe to consider for "fast-moving" items.' },
    { key: 'overstock_multiplier', label: 'Overstock Multiplier', description: 'Reorder point is multiplied by this to define "overstock".' },
    { key: 'high_value_threshold', label: 'High-Value Threshold ($)', description: 'The cost above which an item is considered "high-value".' },
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
        const numericValue = value === '' ? '' : Number(value);
        if (!isNaN(numericValue as number)) {
            setSettings(prev => ({ ...prev, [key]: numericValue }));
        }
    };

    const handleSubmit = (e: React.FormEvent<HTMLFormElement>) => {
        e.preventDefault();
        startTransition(async () => {
            try {
                const settingsToUpdate = {
                    dead_stock_days: Number(settings.dead_stock_days),
                    fast_moving_days: Number(settings.fast_moving_days),
                    overstock_multiplier: Number(settings.overstock_multiplier),
                    high_value_threshold: Number(settings.high_value_threshold),
                }
                await updateCompanySettings(settingsToUpdate);
                toast({
                    title: 'Success',
                    description: 'Your settings have been updated.',
                });
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
            
            <Card>
                <CardHeader>
                    <CardTitle className="flex items-center gap-2">
                        <SettingsIcon className="h-5 w-5" />
                        Business Rules
                    </CardTitle>
                    <CardDescription>
                        Define how the application and AI interpret your business logic. These settings affect reports, alerts, and AI responses.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    {loading ? (
                        <div className="space-y-6">
                            {Array.from({ length: 4 }).map((_, i) => (
                                <div key={i} className="space-y-2">
                                    <Skeleton className="h-4 w-1/4" />
                                    <Skeleton className="h-10 w-full" />
                                    <Skeleton className="h-3 w-1/2" />
                                </div>
                            ))}
                        </div>
                    ) : (
                        <form onSubmit={handleSubmit} className="space-y-6">
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                                {settingsFields.map(({ key, label, description }) => (
                                     <div key={key} className="space-y-2">
                                        <Label htmlFor={key} className="text-base">{label}</Label>
                                        <Input
                                            id={key}
                                            type="number"
                                            value={settings[key] || ''}
                                            onChange={(e) => handleInputChange(key, e.target.value)}
                                            className="text-lg"
                                        />
                                        <p className="text-sm text-muted-foreground">{description}</p>
                                    </div>
                                ))}
                            </div>

                            <div className="flex justify-end pt-4">
                                <Button type="submit" disabled={isPending}>
                                    {isPending ? 'Saving...' : 'Save Settings'}
                                </Button>
                            </div>
                        </form>
                    )}
                </CardContent>
            </Card>
        </div>
    );
}
