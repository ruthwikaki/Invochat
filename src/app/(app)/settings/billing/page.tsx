
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { CheckCircle, DollarSign } from 'lucide-react';
import Link from 'next/link';

export default function BillingPage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Billing & Subscription"
        description="Manage your plan and view your payment history."
      />
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2">
            <Card>
                <CardHeader>
                    <CardTitle>Current Plan</CardTitle>
                    <CardDescription>You are currently on the Pro Plan.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                   <div className="flex items-center justify-between p-4 rounded-lg bg-primary/10 border border-primary/20">
                     <div>
                        <h4 className="font-semibold text-primary text-lg">Pro Plan</h4>
                        <p className="text-muted-foreground">$99 / month</p>
                     </div>
                     <Button>Manage Subscription</Button>
                   </div>
                   <div>
                        <h4 className="font-semibold mb-2">Your plan includes:</h4>
                        <ul className="space-y-2 text-sm text-muted-foreground">
                            <li className="flex items-center gap-2"><CheckCircle className="h-4 w-4 text-success" /> Unlimited AI Queries</li>
                            <li className="flex items-center gap-2"><CheckCircle className="h-4 w-4 text-success" /> Up to 5 Team Members</li>
                            <li className="flex items-center gap-2"><CheckCircle className="h-4 w-4 text-success" /> All E-commerce Integrations</li>
                            <li className="flex items-center gap-2"><CheckCircle className="h-4 w-4 text-success" /> Proactive Email Alerts</li>
                        </ul>
                   </div>
                </CardContent>
                 <CardFooter>
                    <p className="text-xs text-muted-foreground">
                        This is a placeholder page. To implement real billing, integrate a service like Stripe.
                    </p>
                </CardFooter>
            </Card>
        </div>
        <div className="lg:col-span-1">
             <Card>
                <CardHeader>
                    <CardTitle>Payment History</CardTitle>
                    <CardDescription>Your recent invoices.</CardDescription>
                </CardHeader>
                <CardContent>
                    <p className="text-sm text-center text-muted-foreground p-8">No payment history found.</p>
                </CardContent>
            </Card>
        </div>
      </div>
    </AppPage>
  );
}
