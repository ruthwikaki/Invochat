
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { BrainCircuit, RefreshCw, TrendingDown } from 'lucide-react';
import { LandingHeader } from './header';

const features = [
  {
    icon: <BrainCircuit className="h-8 w-8 text-primary" />,
    title: 'Conversational AI',
    description:
      'Ask complex questions about your inventory in plain English and get actionable insights in seconds.',
  },
  {
    icon: <RefreshCw className="h-8 w-8 text-primary" />,
    title: 'Smart Reordering',
    description:
      'Our AI analyzes sales trends and seasonality to generate intelligent reorder suggestions, preventing stockouts.',
  },
  {
    icon: <TrendingDown className="h-8 w-8 text-primary" />,
    title: 'Dead Stock Analysis',
    description:
      'Identify slow-moving inventory that is tying up your capital and get AI-powered markdown suggestions.',
  },
];

export function LandingPage() {
  return (
    <div className="flex min-h-dvh flex-col bg-background text-foreground">
      <LandingHeader />
      <main className="flex-1">
        {/* Hero Section */}
        <section className="relative w-full py-20 md:py-32 lg:py-40 overflow-hidden">
          <div className="absolute inset-0 -z-10 h-full w-full bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,hsl(var(--primary)/0.1),transparent)]"></div>
          <div className="container relative z-10 mx-auto px-4 md:px-6 text-center">
            <div className="max-w-3xl mx-auto space-y-6">
              <h1 className="text-4xl font-bold tracking-tight sm:text-5xl md:text-6xl lg:text-7xl">
                Turn Your Inventory Data into{' '}
                <span className="bg-gradient-to-r from-primary to-purple-400 bg-clip-text text-transparent">
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

        {/* Features Section */}
        <section className="w-full py-20 md:py-32 bg-muted/40 border-t border-b border-border">
          <div className="container mx-auto px-4 md:px-6">
            <div className="mx-auto grid max-w-5xl items-start gap-8 sm:grid-cols-2 md:gap-12 lg:grid-cols-3">
              {features.map((feature, index) => (
                <div key={index} className="grid gap-4 text-center">
                  <div className="mx-auto mb-4 rounded-full bg-primary/10 p-4 w-fit">
                    {feature.icon}
                  </div>
                  <h3 className="text-xl font-semibold text-foreground">{feature.title}</h3>
                  <p className="text-muted-foreground text-sm leading-relaxed">
                    {feature.description}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* CTA Section */}
        <section className="w-full py-20 md:py-32">
          <div className="container mx-auto text-center px-4 md:px-6">
            <h2 className="text-3xl font-bold tracking-tight md:text-4xl">
              Ready to Optimize Your Inventory?
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-muted-foreground md:text-xl">
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

      {/* Footer */}
      <footer className="flex items-center justify-center py-6 border-t border-border bg-background">
        <p className="text-xs text-muted-foreground">
          &copy; {new Date().getFullYear()} ARVO. All rights reserved.
        </p>
      </footer>
    </div>
  );
}
