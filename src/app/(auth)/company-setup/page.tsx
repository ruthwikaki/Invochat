
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Skeleton } from '@/components/ui/skeleton';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import { setupCompanyAndUserProfile } from '@/app/actions';
import { useRouter } from 'next/navigation';
import { useState, useEffect } from 'react';

type CompanyChoice = 'create' | 'join';

function CompanySetupSkeleton() {
    return (
        <Card>
            <CardHeader>
                <Skeleton className="h-7 w-2/5" />
                <Skeleton className="h-4 w-4/5" />
            </CardHeader>
            <CardContent className="space-y-6">
                <div className="space-y-2">
                    <Skeleton className="h-4 w-24" />
                    <div className="flex gap-4">
                        <Skeleton className="h-10 w-24" />
                        <Skeleton className="h-10 w-24" />
                    </div>
                </div>
                <div className="space-y-2">
                    <Skeleton className="h-4 w-32" />
                    <Skeleton className="h-10 w-full" />
                </div>
            </CardContent>
            <CardFooter>
                <Skeleton className="h-10 w-full" />
            </CardFooter>
        </Card>
    );
}

export default function CompanySetupPage() {
    const { user, userProfile, loading, getIdToken, refreshUserProfile } = useAuth();
    const router = useRouter();
    const { toast } = useToast();
    
    const [companyChoice, setCompanyChoice] = useState<CompanyChoice>('create');
    const [companyName, setCompanyName] = useState('');
    const [inviteCode, setInviteCode] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);

    useEffect(() => {
        if (!loading) {
            if (!user) {
                // Not logged in, should not be here.
                router.push('/login');
            } else if (user && userProfile) {
                // Already has a profile, should be on dashboard.
                router.push('/dashboard');
            }
        }
    }, [user, userProfile, loading, router]);


    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsSubmitting(true);

        const idToken = await getIdToken();
        if (!idToken) {
            toast({ variant: 'destructive', title: 'Session Error', description: 'Your session has expired. Please log in again.' });
            setIsSubmitting(false);
            router.push('/login');
            return;
        }

        const companyNameOrCode = companyChoice === 'create' ? companyName : inviteCode;
        if (!companyNameOrCode) {
            toast({ variant: 'destructive', title: 'Missing Information', description: 'Please provide a company name or invite code.' });
            setIsSubmitting(false);
            return;
        }

        try {
            const result = await setupCompanyAndUserProfile({
                idToken,
                companyChoice,
                companyNameOrCode,
            });

            if (result.success && result.profile) {
                toast({ title: 'Setup Complete!', description: `Welcome to ${result.profile.company?.name}!`});
                await refreshUserProfile(); // Refresh context to get new profile and claims
                // The AppLayout guard will now handle the redirect to dashboard
                router.push('/dashboard');
            } else {
                throw new Error(result.error || 'An unknown error occurred during setup.');
            }

        } catch (error: any) {
            toast({ variant: 'destructive', title: 'Setup Failed', description: error.message });
        } finally {
            setIsSubmitting(false);
        }
    };


    if (loading || !user || userProfile) {
        return <CompanySetupSkeleton />;
    }

    return (
        <Card>
            <CardHeader>
                <CardTitle>One Last Step</CardTitle>
                <CardDescription>You're authenticated, but we need to set up your company. Create a new one, or join an existing team.</CardDescription>
            </CardHeader>
            <form onSubmit={handleSubmit}>
                <CardContent className="space-y-6">
                     <div>
                        <Label className="font-medium">Choose an option</Label>
                        <RadioGroup
                            defaultValue="create"
                            className="mt-2 grid grid-cols-2 gap-4"
                            onValueChange={(value: CompanyChoice) => setCompanyChoice(value)}
                        >
                            <div>
                                <RadioGroupItem value="create" id="create" className="peer sr-only" />
                                <Label htmlFor="create" className="flex flex-col items-center justify-between rounded-md border-2 border-muted bg-popover p-4 hover:bg-accent hover:text-accent-foreground peer-data-[state=checked]:border-primary [&:has([data-state=checked])]:border-primary">
                                    Create Company
                                </Label>
                            </div>
                             <div>
                                <RadioGroupItem value="join" id="join" className="peer sr-only" />
                                <Label htmlFor="join" className="flex flex-col items-center justify-between rounded-md border-2 border-muted bg-popover p-4 hover:bg-accent hover:text-accent-foreground peer-data-[state=checked]:border-primary [&:has([data-state=checked])]:border-primary">
                                    Join Company
                                </Label>
                            </div>
                        </RadioGroup>
                    </div>

                    {companyChoice === 'create' ? (
                        <div className="space-y-2">
                            <Label htmlFor="companyName">Company Name</Label>
                            <Input 
                                id="companyName" 
                                placeholder="Your Company, Inc."
                                value={companyName}
                                onChange={(e) => setCompanyName(e.target.value)}
                                required
                            />
                        </div>
                    ) : (
                        <div className="space-y-2">
                            <Label htmlFor="inviteCode">Invite Code</Label>
                            <Input
                                id="inviteCode"
                                placeholder="Enter 6-digit code"
                                value={inviteCode}
                                onChange={(e) => setInviteCode(e.target.value.toUpperCase())}
                                required
                            />
                        </div>
                    )}

                </CardContent>
                <CardFooter>
                    <Button type="submit" className="w-full" disabled={isSubmitting}>
                        {isSubmitting ? 'Setting up...' : 'Complete Setup'}
                    </Button>
                </CardFooter>
            </form>
        </Card>
    );
}
