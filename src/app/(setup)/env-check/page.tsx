
'use client';

import { useTransition } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle, CardDescription, CardFooter } from '@/components/ui/card';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { setupCompanyForExistingUser } from '@/app/(auth)/actions';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useFormStatus } from 'react-dom';

function SubmitButton() {
    const { pending } = useFormStatus();
    return (
        <Button type="submit" className="w-full" disabled={pending}>
             {pending ? <Loader2 className="animate-spin" /> : 'Create Company and Continue'}
        </Button>
    )
}

export default function EnvCheckPage() {
    const [isPending, startTransition] = useTransition();

    const formAction = (formData: FormData) => {
        startTransition(() => {
            setupCompanyForExistingUser(formData);
        });
    }

    return (
        <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
          <Card className="w-full max-w-2xl">
            <CardHeader>
              <div className="mx-auto bg-destructive/10 p-3 rounded-full w-fit mb-4">
                <AlertTriangle className="h-8 w-8 text-destructive" />
              </div>
              <CardTitle className="text-center text-2xl">One Last Step: Create Your Company</CardTitle>
              <CardDescription className="text-center">
                Your user account exists, but it needs to be linked to a company. Please enter your company's name below to complete the setup.
              </CardDescription>
            </CardHeader>
            <form action={formAction}>
                <CardContent>
                    <div className="space-y-2">
                        <Label htmlFor="companyName">Company Name</Label>
                        <Input 
                            id="companyName"
                            name="companyName"
                            placeholder="Your Company Inc."
                            required
                        />
                    </div>
                </CardContent>
                <CardFooter>
                    <SubmitButton />
                </CardFooter>
            </form>
          </Card>
        </div>
    );
}
