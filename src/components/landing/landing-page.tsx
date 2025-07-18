
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { BrainCircuit, RefreshCw, TrendingDown } from 'lucide-react';
import { LandingHeader } from './header';

const features = [
  {
    icon: <BrainCircuit className="h-8 w-8 text-primary" />,
    title: 'Conversational AI',
    description: 'Ask complex questions about your inventory in plain English and get actionable insights in seconds.',
  },
  {
    icon: <RefreshCw className="h-8 w-8 text-primary" />,
    title: 'Smart Reordering',
    description: 'Our AI analyzes sales trends and seasonality to generate intelligent reorder suggestions, preventing stockouts.',
  },
  {
    icon: <TrendingDown className="h-8 w-8 text-primary" />,
    title: 'Dead Stock Analysis',
    description: 'Identify slow-moving inventory that is tying up your capital and get AI-powered markdown suggestions.',
  },
];

export function LandingPage() {
  return (
    <div className="flex min-h-full flex-col">
      <LandingHeader />
      <main className="flex-1">
        <section className="relative w-full py-20 md:py-32 lg:py-40">
           <div className="absolute inset-0 -z-10">
            <div className="absolute inset-0 bg-gradient-to-br from-background via-primary/5 to-background" />
            <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(107,70,193,0.1),rgba(255,255,255,0))]" />
          </div>
          <div className="container mx-auto px-4 md:px-6 text-center">
            <div className="max-w-3xl mx-auto space-y-6">
              <h1 className="text-4xl font-bold tracking-tighter sm:text-5xl md:text-6xl lg:text-7xl">
                Turn Your Inventory Data into{' '}
                <span className="bg-gradient-to-r from-primary to-violet-500 bg-clip-text text-transparent">
                  Actionable Intelligence
                </span>
              </h1>
              <p className="text-lg text-muted-foreground md:text-xl">
                ARVO is the AI-native inventory management platform that helps you stop guessing and start making data-driven decisions.
              </p>
              <div>
                <Button asChild size="lg">
                  <Link href="/signup">Get Started Free</Link>
                </Button>
              </div>
            </div>
          </div>
        </section>

        <section id="features" className="w-full py-20 md:py-32 bg-muted/40">
          <div className="container mx-auto px-4 md:px-6">
            <div className="mx-auto grid max-w-5xl items-center gap-6 lg:grid-cols-3 lg:gap-12">
              {features.map((feature, index) => (
                <Card key={index} className="h-full">
                  <CardHeader className="items-center text-center">
                    <div className="mb-4 rounded-full bg-primary/10 p-4">
                      {feature.icon}
                    </div>
                    <CardTitle>{feature.title}</CardTitle>
                  </CardHeader>
                  <CardContent className="text-center">
                    <p className="text-muted-foreground">{feature.description}</p>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </section>

        <section className="w-full py-20 md:py-32">
          <div className="container mx-auto text-center">
            <h2 className="text-3xl font-bold tracking-tighter md:text-4xl">
              Ready to Optimize Your Inventory?
            </h2>
            <p className="mx-auto mt-4 max-w-[600px] text-muted-foreground md:text-xl">
              Sign up today and get insights from your data in minutes. No credit card required.
            </p>
            <div className="mt-6">
              <Button asChild size="lg">
                <Link href="/signup">Start Your Free Trial</Link>
              </Button>
            </div>
          </div>
        </section>
      </main>
      <footer className="flex items-center justify-center py-6 border-t bg-background">
        <p className="text-xs text-muted-foreground">
          &copy; {new Date().getFullYear()} ARVO. All rights reserved.
        </p>
      </footer>
    </div>
  );
}
