
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { CheckCircle, DollarSign, Users, BrainCircuit, BarChartHorizontal } from 'lucide-react';
import Link from 'next/link';

const plans = [
    {
        name: "Starter",
        price: "$49",
        features: ["1,000 AI Queries/mo", "5,000 SKUs", "5 Users", "Basic Analytics"],
        current: false,
    },
    {
        name: "Growth",
        price: "$99",
        features: ["5,000 AI Queries/mo", "20,000 SKUs", "15 Users", "Advanced Analytics", "Email Alerts"],
        current: true,
    },
     {
        name: "Enterprise",
        price: "Contact Us",
        features: ["Unlimited AI Queries", "Unlimited SKUs", "Unlimited Users", "Dedicated Support", "Custom Integrations"],
        current: false,
    }
]

export default function BillingPage() {
  const currentPlan = plans.find(p => p.current)!;

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
                    <CardDescription>You are currently on the {currentPlan.name} Plan.</CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                   <div className="flex items-center justify-between p-4 rounded-lg bg-primary/10 border border-primary/20">
                     <div>
                        <h4 className="font-semibold text-primary text-lg">{currentPlan.name} Plan</h4>
                        <p className="text-muted-foreground">{currentPlan.price} / month</p>
                     </div>
                     <Button>Manage in Stripe</Button>
                   </div>
                   <div className="grid grid-cols-2 gap-4 pt-4">
                        <div className="space-y-2 p-4 rounded-lg bg-muted/50">
                            <h4 className="font-semibold text-sm flex items-center gap-2 text-muted-foreground"><BrainCircuit className="h-4 w-4" /> AI Queries</h4>
                            <p><span className="font-bold text-lg">452</span> / 5,000 used</p>
                            <div className="w-full bg-muted rounded-full h-2.5"><div className="bg-primary h-2.5 rounded-full" style={{width: '9%'}}></div></div>
                        </div>
                         <div className="space-y-2 p-4 rounded-lg bg-muted/50">
                            <h4 className="font-semibold text-sm flex items-center gap-2 text-muted-foreground"><Users className="h-4 w-4" /> Users</h4>
                            <p><span className="font-bold text-lg">3</span> / 15 used</p>
                            <div className="w-full bg-muted rounded-full h-2.5"><div className="bg-primary h-2.5 rounded-full" style={{width: '20%'}}></div></div>
                        </div>
                   </div>
                </CardContent>
                 <CardFooter>
                    <p className="text-xs text-muted-foreground">
                        This is a placeholder page. Integrate Stripe for real billing functionality.
                    </p>
                </CardFooter>
            </Card>
        </div>
        <div className="lg:col-span-1">
             <Card>
                <CardHeader>
                    <CardTitle>Invoices</CardTitle>
                    <CardDescription>Your recent payment history.</CardDescription>
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
