'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import Link from 'next/link';
import { useState } from 'react';

export default function ResetPasswordPage() {
    const [email, setEmail] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [isSubmitted, setIsSubmitted] = useState(false);
    const { resetPassword } = useAuth();
    const { toast } = useToast();

    const handleReset = async (e: React.FormEvent) => {
        e.preventDefault();
        setIsSubmitting(true);
        try {
            await resetPassword(email);
            setIsSubmitted(true);
        } catch (error: any) {
            console.error(error);
             toast({
                variant: 'destructive',
                title: 'Error',
                description: 'Could not send password reset email. Please check the address and try again.',
            });
        } finally {
            setIsSubmitting(false);
        }
    };

    if (isSubmitted) {
        return (
             <Card>
                <CardHeader>
                    <CardTitle>Check Your Email</CardTitle>
                    <CardDescription>A password reset link has been sent to {email} if an account with that email exists.</CardDescription>
                </CardHeader>
                <CardFooter>
                    <Button asChild className="w-full">
                        <Link href="/auth/login">Back to Login</Link>
                    </Button>
                </CardFooter>
            </Card>
        )
    }

    return (
        <Card>
            <CardHeader>
                <CardTitle>Reset Your Password</CardTitle>
                <CardDescription>Enter your email address and we will send you a link to reset your password.</CardDescription>
            </CardHeader>
            <form onSubmit={handleReset}>
                <CardContent>
                    <div className="space-y-2">
                        <Label htmlFor="email">Email</Label>
                        <Input
                            id="email"
                            type="email"
                            placeholder="you@company.com"
                            value={email}
                            onChange={(e) => setEmail(e.target.value)}
                            required
                        />
                    </div>
                </CardContent>
                <CardFooter className="flex-col gap-4">
                    <Button type="submit" className="w-full" disabled={isSubmitting}>
                        {isSubmitting ? 'Sending...' : 'Send Reset Link'}
                    </Button>
                    <Link href="/auth/login" className="text-sm text-primary hover:underline">
                        Remembered your password? Log in
                    </Link>
                </CardFooter>
            </form>
        </Card>
    );
}
