'use client';

import React from 'react';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { 
  MessageSquare, 
  TrendingDown, 
  Package, 
  BarChart3, 
  Truck, 
  AlertCircle,
  ArrowRight,
  Star,
  CheckCircle
} from 'lucide-react';
import { LandingHeader } from './header';

const features = [
  {
    icon: <MessageSquare className="w-8 h-8 text-primary" />,
    title: "Natural Language Chat",
    description: "Ask complex questions about your inventory in plain English. No need to learn complicated dashboards or reports.",
  },
  {
    icon: <TrendingDown className="w-8 h-8 text-primary" />,
    title: "Dead Stock Analysis",
    description: "Identify slow-moving inventory tying up your capital and get AI-powered markdown and liquidation strategies.",
  },
  {
    icon: <Package className="w-8 h-8 text-primary" />,
    title: "Smart Reordering",
    description: "AI analyzes sales trends, seasonality, and supplier lead times to generate perfect reorder suggestions.",
  },
  {
    icon: <Truck className="w-8 h-8 text-primary" />,
    title: "Supplier Performance",
    description: "Track delivery times, quality issues, and costs across all vendors to optimize your supply chain.",
  },
  {
    icon: <BarChart3 className="w-8 h-8 text-primary" />,
    title: "Predictive Analytics",
    description: "Advanced forecasting prevents stockouts and overstock situations before they happen.",
  },
  {
    icon: <AlertCircle className="w-8 h-8 text-primary" />,
    title: "Intelligent Alerts",
    description: "Get personalized notifications about critical inventory events that are tailored to your business needs.",
  }
];

const testimonials = [
  {
    name: "Sarah Chen",
    role: "Operations Director, TechGear Plus",
    content: "ARVO helped us reduce dead stock by 60% in just 3 months. The AI insights are incredible and have become essential to our planning.",
    avatar: "SC"
  },
  {
    name: "Marcus Rodriguez",
    role: "Inventory Manager, HomeStyle Depot",
    content: "Finally, an inventory system that speaks my language. No more complex reports - just ask and get answers. It saves me hours every week.",
    avatar: "MR"
  },
  {
    name: "Jennifer Park",
    role: "CEO, EcoLiving Co",
    content: "We've prevented over $200K in stockouts since implementing ARVO. The predictive reordering is phenomenal. It's like having another analyst on the team.",
    avatar: "JP"
  }
];

export function LandingPage() {

  return (
    <div className="flex min-h-dvh flex-col bg-gray-50 text-gray-800">
      <LandingHeader />
      <main className="flex-1">
        {/* Hero Section */}
        <section className="relative w-full pt-40 pb-20 md:pt-48 md:pb-32 lg:pt-56 lg:pb-40 overflow-hidden">
          <div className="absolute inset-0 -z-10 h-full w-full bg-gradient-to-br from-purple-50 via-blue-50 to-indigo-100"></div>
          <div className="container relative z-10 mx-auto px-4 md:px-6 text-center">
            <div className="max-w-3xl mx-auto space-y-6">
              <h1 className="text-4xl font-bold tracking-tight sm:text-5xl md:text-6xl lg:text-7xl text-gray-900">
                Turn Inventory Data into{' '}
                <span className="bg-gradient-to-r from-primary via-purple-500 to-indigo-500 bg-clip-text text-transparent">
                  Actionable Intelligence
                </span>
              </h1>
              <p className="text-lg text-gray-600 md:text-xl">
                ARVO is the AI-native inventory management platform that helps you stop guessing and start making data-driven decisions.
              </p>
              <div>
                <Button asChild size="lg" className="group rounded-full px-8 py-6 text-base font-semibold shadow-lg hover:shadow-2xl transition-shadow duration-300">
                  <Link href="/signup">
                    Get Started Free
                    <ArrowRight className="w-5 h-5 ml-2 group-hover:translate-x-1 transition-transform" />
                  </Link>
                </Button>
              </div>
            </div>
          </div>
        </section>

        {/* Features Section */}
        <section id="features" className="w-full py-20 md:py-32 bg-white border-t border-b">
          <div className="container mx-auto px-4 md:px-6">
             <div className="text-center mb-16">
              <h2 className="text-3xl font-bold tracking-tight md:text-4xl text-gray-900">Everything You Need to Optimize Inventory</h2>
              <p className="mt-4 text-gray-600 md:text-xl">
                Powerful AI tools that transform how you manage your business.
              </p>
            </div>
            <div className="mx-auto grid max-w-5xl items-start gap-8 sm:grid-cols-2 md:gap-12 lg:grid-cols-3">
              {features.map((feature, index) => (
                <div key={index} className="grid gap-4 text-center">
                  <div className="mx-auto mb-4 rounded-full bg-primary/10 p-4 w-fit">
                    {feature.icon}
                  </div>
                  <h3 className="text-xl font-semibold text-gray-900">{feature.title}</h3>
                  <p className="text-gray-600 text-sm leading-relaxed">
                    {feature.description}
                  </p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Testimonials Section */}
        <section id="testimonials" className="py-20 md:py-32 bg-gray-50">
          <div className="container mx-auto px-4 md:px-6">
            <div className="text-center mb-16">
              <h2 className="text-3xl font-bold tracking-tight md:text-4xl text-gray-900">Trusted by Growing Businesses</h2>
              <p className="mt-4 text-gray-600 md:text-xl">
                See how ARVO is making a real impact.
              </p>
            </div>
            <div className="grid md:grid-cols-3 gap-8">
              {testimonials.map((testimonial, idx) => (
                <div key={idx} className="bg-white p-8 rounded-2xl border border-gray-200 shadow-sm hover:shadow-xl transition-shadow duration-300">
                  <div className="flex items-center mb-4">
                    {[...Array(5)].map((_, i) => (
                      <Star key={i} className="w-5 h-5 text-yellow-400 fill-current" />
                    ))}
                  </div>
                  <p className="text-gray-700 mb-6 leading-relaxed">"{testimonial.content}"</p>
                  <div className="flex items-center">
                    <div className="w-12 h-12 bg-gradient-to-r from-primary to-purple-500 rounded-full flex items-center justify-center text-white font-bold mr-4">
                      {testimonial.avatar}
                    </div>
                    <div>
                      <div className="font-semibold text-gray-900">{testimonial.name}</div>
                      <div className="text-sm text-gray-600">{testimonial.role}</div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* CTA Section */}
        <section className="w-full py-20 md:py-32 bg-white">
          <div className="container mx-auto text-center px-4 md:px-6">
            <h2 className="text-3xl font-bold tracking-tight md:text-4xl text-gray-900">
              Ready to Optimize Your Inventory?
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-gray-600 md:text-xl">
              Sign up today and get insights from your data in minutes. No credit card required.
            </p>
            <div className="mt-8 flex flex-col sm:flex-row items-center justify-center gap-4">
              <Button asChild size="lg" className="group rounded-full px-8 py-6 text-base font-semibold shadow-lg hover:shadow-2xl transition-shadow duration-300">
                <Link href="/signup">Start Your Free Trial</Link>
              </Button>
              <div className="flex items-center gap-2 text-sm text-gray-500">
                <CheckCircle className="w-4 h-4 text-green-500" />
                <span>15-minute setup</span>
              </div>
            </div>
          </div>
        </section>
      </main>

      {/* Footer */}
      <footer className="flex items-center justify-center py-6 border-t bg-white">
        <p className="text-xs text-gray-500">
          &copy; {new Date().getFullYear()} ARVO. All rights reserved.
        </p>
      </footer>
    </div>
  );
}
