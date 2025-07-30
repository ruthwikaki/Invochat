
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function TermsOfServicePage() {
  return (
    <AppPage>
        <AppPageHeader
            title="Terms of Service"
            description="Last updated: July 30, 2024"
        />
        <div className="mt-6">
            <Card>
                 <CardHeader>
                    <CardTitle>Your Terms of Service</CardTitle>
                    <CardDescription>
                        Please replace this placeholder text with the terms of service provided by your legal service (e.g., Termly).
                    </CardDescription>
                </CardHeader>
                <CardContent className="prose dark:prose-invert max-w-none">
                    <p>
                        This document outlines the rules and regulations for the use of your application. It forms a legal agreement between you and your users.
                    </p>
                    <h2>1. Acceptance of Terms</h2>
                    <p>
                        By accessing or using the service, users agree to be bound by these terms. If they disagree with any part of the terms, then they may not access the service.
                    </p>
                    <h2>2. User Accounts</h2>
                    <p>
                       When a user creates an account, they must provide information that is accurate, complete, and current at all times. Failure to do so constitutes a breach of the terms, which may result in immediate termination of their account.
                    </p>
                    <h2>3. Intellectual Property</h2>
                    <p>
                        The service and its original content, features, and functionality are and will remain the exclusive property of your company and its licensors.
                    </p>
                    <h2>4. Termination</h2>
                    <p>
                        You may terminate or suspend a user's account immediately, without prior notice or liability, for any reason whatsoever, including without limitation if they breach the terms.
                    </p>
                    <h2>5. Limitation of Liability</h2>
                    <p>
                        In no event shall your company, nor its directors, employees, partners, agents, suppliers, or affiliates, be liable for any indirect, incidental, special, consequential or punitive damages.
                    </p>
                     <h2>6. Governing Law</h2>
                    <p>
                       These terms shall be governed and construed in accordance with the laws of your jurisdiction, without regard to its conflict of law provisions.
                    </p>
                </CardContent>
            </Card>
        </div>
    </AppPage>
  );
}
