
'use client';

import React, { useState, useEffect, useRef } from 'react';
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
  CheckCircle,
  Zap,
  Brain,
  Users,
  DollarSign,
  Clock,
  Star,
  Menu,
  X,
  Play,
  ChevronDown
} from 'lucide-react';
import { InvoChatLogo } from '@/components/invochat-logo';

const ARVOLandingPage = () => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    const handleScroll = () => setScrollY(window.scrollY);
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const useCounter = (end: number, duration = 2000) => {
    const [count, setCount] = useState(0);
    const [isVisible, setIsVisible] = useState(false);
    const ref = useRef<HTMLDivElement>(null);

    useEffect(() => {
      const observer = new IntersectionObserver(
        ([entry]) => {
          if (entry.isIntersecting) {
            setIsVisible(true);
            observer.disconnect();
          }
        },
        { threshold: 0.1 }
      );

      if (ref.current) {
        observer.observe(ref.current);
      }

      return () => {
        if (ref.current) {
            observer.unobserve(ref.current);
        }
      };
    }, []);

    useEffect(() => {
      if (!isVisible) return;

      let startTime: number | null = null;
      const animate = (currentTime: number) => {
        if (startTime === null) startTime = currentTime;
        const progress = Math.min((currentTime - startTime) / duration, 1);
        setCount(Math.floor(progress * end));
        if (progress < 1) {
          requestAnimationFrame(animate);
        }
      };
      requestAnimationFrame(animate);
    }, [isVisible, end, duration]);

    return [count, ref] as const;
  };

  const features = [
    {
      icon: <MessageSquare className="w-8 h-8" />,
      title: "Natural Language Chat",
      description: "Ask complex questions about your inventory in plain English. No need to learn complicated dashboards or reports.",
      color: "from-blue-500 to-cyan-500",
      demo: "\"Which products are running low?\" → Instant intelligent answers"
    },
    {
      icon: <TrendingDown className="w-8 h-8" />,
      title: "Dead Stock Analysis",
      description: "Identify slow-moving inventory tying up your capital. Get AI-powered markdown and liquidation strategies.",
      color: "from-red-500 to-orange-500",
      demo: "Find $50K+ in trapped inventory you didn't know existed"
    },
    {
      icon: <Package className="w-8 h-8" />,
      title: "Smart Reordering",
      description: "AI analyzes sales trends, seasonality, and supplier lead times to generate perfect reorder suggestions.",
      color: "from-green-500 to-emerald-500",
      demo: "Prevent stockouts while minimizing excess inventory"
    },
    {
      icon: <Truck className="w-8 h-8" />,
      title: "Supplier Performance",
      description: "Track delivery times, quality issues, and costs across all vendors. Optimize your supply chain automatically.",
      color: "from-purple-500 to-violet-500",
      demo: "\"Which supplier delivers fastest?\" → Data-driven decisions"
    },
    {
      icon: <BarChart3 className="w-8 h-8" />,
      title: "Predictive Analytics",
      description: "Advanced forecasting prevents stockouts and overstock situations before they happen.",
      color: "from-indigo-500 to-blue-500",
      demo: "\"You'll run out of XYZ in 7 days\" - proactive alerts"
    },
    {
      icon: <AlertCircle className="w-8 h-8" />,
      title: "Intelligent Alerts",
      description: "Get personalized notifications about critical inventory events, tailored to your business needs.",
      color: "from-yellow-500 to-amber-500",
      demo: "Smart alerts that matter, when they matter"
    }
  ];

  const testimonials = [
    {
      name: "Sarah Chen",
      role: "Operations Director",
      company: "TechGear Plus",
      content: "ARVO helped us reduce dead stock by 60% in just 3 months. The AI insights are incredible.",
      avatar: "SC",
      rating: 5
    },
    {
      name: "Marcus Rodriguez",
      role: "Inventory Manager",
      company: "HomeStyle Depot",
      content: "Finally, an inventory system that speaks my language. No more complex reports - just ask and get answers.",
      avatar: "MR",
      rating: 5
    },
    {
      name: "Jennifer Park",
      role: "CEO",
      company: "EcoLiving Co",
      content: "We've prevented over $200K in stockouts since implementing ARVO. The ROI is phenomenal.",
      avatar: "JP",
      rating: 5
    }
  ];

  const stats = [
    { value: 47, suffix: "%", label: "Average Inventory Reduction" },
    { value: 200, suffix: "K+", label: "Saved in Costs", prefix: "$" },
    { value: 99, suffix: "%", label: "Stockout Prevention" },
    { value: 15, suffix: "min", label: "Setup Time" }
  ];

  const integrations = [
    { name: "Shopify", logo: "🛒", connected: true },
    { name: "WooCommerce", logo: "🌐", connected: true },
    { name: "Amazon FBA", logo: "📦", connected: true },
    { name: "QuickBooks", logo: "💼", connected: false },
    { name: "SAP", logo: "⚙️", connected: false },
    { name: "NetSuite", logo: "🏢", connected: false }
  ];

  const ChatDemo = () => {
    const [messages, setMessages] = useState<{type: string, text: string}[]>([]);
    const [currentMessage, setCurrentMessage] = useState(0);
    const [isTyping, setIsTyping] = useState(false);
    
    const demoMessages = [
      { type: 'user', text: "Show me dead stock items" },
      { type: 'ai', text: "I found 23 dead stock items worth $47,350. Here are the top 5 by value:", delay: 1000 },
      { type: 'user', text: "What should I order from Johnson Supply?" },
      { type: 'ai', text: "Based on current inventory and sales velocity, I recommend ordering: Widget A (150 units), Component B (75 units), and Part C (200 units). Total: $8,450.", delay: 1500 }
    ];

    useEffect(() => {
      if (currentMessage < demoMessages.length) {
        const timer = setTimeout(() => {
          setIsTyping(true);
          setTimeout(() => {
            setMessages(prev => [...prev, demoMessages[currentMessage]]);
            setIsTyping(false);
            setCurrentMessage(prev => prev + 1);
          }, (demoMessages[currentMessage] as any).delay || 800);
        }, 500);
        return () => clearTimeout(timer);
      } else {
        const resetTimer = setTimeout(() => {
          setMessages([]);
          setCurrentMessage(0);
        }, 3000);
        return () => clearTimeout(resetTimer);
      }
    }, [currentMessage]);

    return (
      <div className="bg-white rounded-2xl shadow-2xl p-6 max-w-md mx-auto">
        <div className="flex items-center gap-3 mb-4 pb-3 border-b">
          <div className="w-8 h-8 bg-gradient-to-r from-purple-600 to-violet-600 rounded-full flex items-center justify-center text-white font-bold text-sm">
            A
          </div>
          <div>
            <h3 className="font-semibold text-gray-900">ARVO Assistant</h3>
            <p className="text-xs text-green-500 flex items-center gap-1">
              <span className="w-2 h-2 bg-green-500 rounded-full"></span>
              Online
            </p>
          </div>
        </div>
        
        <div className="space-y-3 h-64 overflow-y-auto">
          {messages.map((message, idx) => (
            <div key={idx} className={`flex ${message.type === 'user' ? 'justify-end' : 'justify-start'}`}>
              <div className={`max-w-xs px-4 py-2 rounded-2xl text-sm ${
                message.type === 'user' 
                  ? 'bg-purple-600 text-white' 
                  : 'bg-gray-100 text-gray-800'
              }`}>
                {message.text}
              </div>
            </div>
          ))}
          {isTyping && (
            <div className="flex justify-start">
              <div className="bg-gray-100 px-4 py-2 rounded-2xl">
                <div className="flex space-x-1">
                  <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                  <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{animationDelay: '0.1s'}}></div>
                  <div className="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style={{animationDelay: '0.2s'}}></div>
                </div>
              </div>
            </div>
          )}
        </div>
        
        <div className="mt-4 pt-3 border-t">
          <div className="flex items-center gap-2 bg-gray-50 rounded-xl px-3 py-2">
            <input 
              placeholder="Ask about your inventory..." 
              className="flex-1 bg-transparent text-sm outline-none text-gray-600"
              readOnly
            />
            <MessageSquare className="w-4 h-4 text-purple-600" />
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-gray-50 text-gray-800 font-sans">
      <nav className={`fixed w-full z-50 transition-all duration-300 ${
        scrollY > 50 ? 'bg-white/95 backdrop-blur-lg shadow-lg' : 'bg-transparent'
      }`}>
        <div className="container mx-auto px-6">
          <div className="flex justify-between items-center py-4">
            <Link href="/" className="flex items-center space-x-3">
              <InvoChatLogo className="h-8 w-8 text-primary"/>
              <span className="text-2xl font-bold bg-gradient-to-r from-purple-600 to-violet-600 bg-clip-text text-transparent">
                ARVO
              </span>
            </Link>
            
            <div className="hidden md:flex items-center space-x-8">
              <Link href="#features" className="text-gray-600 hover:text-purple-600 transition-colors">Features</Link>
              <Link href="#demo" className="text-gray-600 hover:text-purple-600 transition-colors">Demo</Link>
              <Link href="#testimonials" className="text-gray-600 hover:text-purple-600 transition-colors">Reviews</Link>
              <Button asChild className="bg-gradient-to-r from-purple-600 to-violet-600 text-white px-6 py-2 rounded-xl hover:shadow-lg transform hover:scale-105 transition-all duration-200">
                <Link href="/signup">Get Started Free</Link>
              </Button>
            </div>

            <button 
              className="md:hidden"
              onClick={() => setIsMenuOpen(!isMenuOpen)}
            >
              {isMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>
      </nav>

      {isMenuOpen && (
        <div className="fixed inset-0 z-40 bg-white md:hidden">
          <div className="pt-24 px-6">
            <div className="space-y-6 text-center">
              <Link href="#features" className="block text-xl text-gray-600" onClick={() => setIsMenuOpen(false)}>Features</Link>
              <Link href="#demo" className="block text-xl text-gray-600" onClick={() => setIsMenuOpen(false)}>Demo</Link>
              <Link href="#testimonials" className="block text-xl text-gray-600" onClick={() => setIsMenuOpen(false)}>Reviews</Link>
              <Button asChild className="w-full bg-gradient-to-r from-purple-600 to-violet-600 text-white py-3 rounded-xl">
                <Link href="/signup" onClick={() => setIsMenuOpen(false)}>Get Started Free</Link>
              </Button>
            </div>
          </div>
        </div>
      )}

      <main>
        <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
          <div className="absolute inset-0 opacity-30">
            <div className="absolute inset-0 bg-gradient-to-br from-purple-100 via-blue-50 to-indigo-100"></div>
            <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-purple-300 rounded-full mix-blend-multiply filter blur-xl opacity-70 animate-pulse"></div>
            <div className="absolute top-1/3 right-1/4 w-96 h-96 bg-yellow-300 rounded-full mix-blend-multiply filter blur-xl opacity-70 animate-pulse" style={{animationDelay: '2s'}}></div>
            <div className="absolute bottom-1/4 left-1/3 w-96 h-96 bg-pink-300 rounded-full mix-blend-multiply filter blur-xl opacity-70 animate-pulse" style={{animationDelay: '4s'}}></div>
          </div>

          <div className="container mx-auto px-6 relative z-10">
            <div className="max-w-4xl mx-auto text-center">
              <div className="mb-8 inline-flex items-center gap-2 bg-white/80 backdrop-blur-sm px-4 py-2 rounded-full border shadow-sm">
                <Zap className="w-4 h-4 text-purple-600" />
                <span className="text-sm font-medium text-gray-700">AI-Powered Inventory Intelligence</span>
              </div>
              
              <h1 className="text-5xl md:text-7xl font-bold mb-8 leading-tight">
                Turn Your Inventory Data Into{' '}
                <span className="bg-gradient-to-r from-purple-600 via-violet-600 to-indigo-600 bg-clip-text text-transparent">
                  Actionable Intelligence
                </span>
              </h1>
              
              <p className="text-xl md:text-2xl text-gray-600 mb-12 max-w-3xl mx-auto leading-relaxed">
                Stop guessing about your inventory. ARVO uses advanced AI to analyze your data and provide 
                instant insights through natural conversation. No more complex dashboards—just ask and get answers.
              </p>
              
              <div className="flex flex-col sm:flex-row gap-4 justify-center mb-16">
                 <Button asChild size="lg" className="group bg-gradient-to-r from-purple-600 to-violet-600 text-white px-8 py-4 rounded-xl text-lg font-semibold hover:shadow-2xl transform hover:scale-105 transition-all duration-300">
                    <Link href="/signup">
                        Start Free Trial
                        <ArrowRight className="w-5 h-5 ml-2 group-hover:translate-x-1 transition-transform" />
                    </Link>
                </Button>
                <Button size="lg" variant="outline" className="group bg-white text-gray-700 px-8 py-4 rounded-xl text-lg font-semibold border-2 border-gray-200 hover:border-purple-300 hover:shadow-lg transition-all duration-300">
                    <Play className="w-5 h-5 mr-2" />
                    Watch Demo
                </Button>
              </div>

              <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mb-16">
                {stats.map((stat, idx) => {
                  const [count, ref] = useCounter(stat.value);
                  return (
                    <div key={idx} ref={ref} className="text-center">
                      <div className="text-3xl md:text-4xl font-bold text-gray-900 mb-2">
                        {stat.prefix}{count}{stat.suffix}
                      </div>
                      <div className="text-sm text-gray-600">{stat.label}</div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>

          <div className="absolute bottom-8 left-1/2 transform -translate-x-1/2">
            <ChevronDown className="w-8 h-8 text-gray-400 animate-bounce" />
          </div>
        </section>
        
        <section id="demo" className="py-20 bg-gradient-to-r from-purple-600 to-violet-600">
          <div className="container mx-auto px-6">
            <div className="max-w-6xl mx-auto">
              <div className="text-center mb-16">
                <h2 className="text-4xl md:text-5xl font-bold text-white mb-6">
                  See ARVO in Action
                </h2>
                <p className="text-xl text-purple-100 max-w-3xl mx-auto">
                  Watch how natural conversation transforms complex inventory analysis into simple, actionable insights.
                </p>
              </div>
              
              <div className="grid md:grid-cols-2 gap-12 items-center">
                <div className="space-y-6 text-white">
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 bg-white/20 rounded-full flex items-center justify-center flex-shrink-0 mt-1">
                      <MessageSquare className="w-4 h-4" />
                    </div>
                    <div>
                      <h3 className="text-xl font-semibold mb-2">Natural Language Queries</h3>
                      <p className="text-purple-100">Ask questions in plain English. No SQL, no complex filters, no training required.</p>
                    </div>
                  </div>
                  
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 bg-white/20 rounded-full flex items-center justify-center flex-shrink-0 mt-1">
                      <Brain className="w-4 h-4" />
                    </div>
                    <div>
                      <h3 className="text-xl font-semibold mb-2">Intelligent Responses</h3>
                      <p className="text-purple-100">Get detailed analysis with actionable recommendations, not just raw data.</p>
                    </div>
                  </div>
                  
                  <div className="flex items-start gap-4">
                    <div className="w-8 h-8 bg-white/20 rounded-full flex items-center justify-center flex-shrink-0 mt-1">
                      <Zap className="w-4 h-4" />
                    </div>
                    <div>
                      <h3 className="text-xl font-semibold mb-2">Instant Insights</h3>
                      <p className="text-purple-100">Complex analysis that used to take hours now happens in seconds.</p>
                    </div>
                  </div>
                </div>
                
                <div>
                  <ChatDemo />
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="features" className="py-20 bg-white">
          <div className="container mx-auto px-6">
            <div className="text-center mb-16">
              <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-6">
                Everything You Need to Optimize Inventory
              </h2>
              <p className="text-xl text-gray-600 max-w-3xl mx-auto">
                Powerful AI tools that transform how you manage inventory, reduce costs, and prevent stockouts.
              </p>
            </div>
            
            <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
              {features.map((feature, idx) => (
                <div key={idx} className="group bg-white p-8 rounded-2xl border border-gray-100 hover:border-purple-200 hover:shadow-2xl transition-all duration-300 transform hover:-translate-y-2">
                  <div className={`w-16 h-16 bg-gradient-to-r ${feature.color} rounded-2xl flex items-center justify-center text-white mb-6 group-hover:scale-110 transform transition-transform duration-300`}>
                    {feature.icon}
                  </div>
                  <h3 className="text-xl font-bold text-gray-900 mb-4">{feature.title}</h3>
                  <p className="text-gray-600 mb-4 leading-relaxed">{feature.description}</p>
                  <div className="text-sm text-purple-600 font-medium bg-purple-50 px-3 py-2 rounded-lg">
                    {feature.demo}
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="py-20 bg-gray-50">
          <div className="container mx-auto px-6">
            <div className="max-w-4xl mx-auto text-center">
              <h2 className="text-4xl font-bold text-gray-900 mb-6">
                Works With Your Existing Tools
              </h2>
              <p className="text-xl text-gray-600 mb-12">
                ARVO seamlessly integrates with your current e-commerce platforms and business systems.
              </p>
              
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-6">
                {integrations.map((integration, idx) => (
                  <div key={idx} className={`p-6 rounded-xl border transition-all duration-300 ${
                    integration.connected 
                      ? 'bg-white border-green-200 hover:shadow-lg' 
                      : 'bg-gray-100 border-gray-200'
                  }`}>
                    <div className="text-3xl mb-3">{integration.logo}</div>
                    <div className="text-sm font-medium text-gray-700 mb-2">{integration.name}</div>
                    {integration.connected && (
                      <div className="flex items-center justify-center text-xs text-green-600">
                        <CheckCircle className="w-3 h-3 mr-1" />
                        Connected
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        <section id="testimonials" className="py-20 bg-white">
          <div className="container mx-auto px-6">
            <div className="text-center mb-16">
              <h2 className="text-4xl font-bold text-gray-900 mb-6">
                Trusted by Growing Businesses
              </h2>
              <p className="text-xl text-gray-600">
                See how ARVO is transforming inventory management for companies like yours.
              </p>
            </div>
            
            <div className="grid md:grid-cols-3 gap-8">
              {testimonials.map((testimonial, idx) => (
                <div key={idx} className="bg-white p-8 rounded-2xl border border-gray-100 shadow-lg hover:shadow-2xl transition-shadow duration-300">
                  <div className="flex items-center mb-4">
                    {[...Array(testimonial.rating)].map((_, i) => (
                      <Star key={i} className="w-5 h-5 text-yellow-400 fill-current" />
                    ))}
                  </div>
                  <p className="text-gray-700 mb-6 leading-relaxed">"{testimonial.content}"</p>
                  <div className="flex items-center">
                    <div className="w-12 h-12 bg-gradient-to-r from-purple-600 to-violet-600 rounded-full flex items-center justify-center text-white font-bold mr-4">
                      {testimonial.avatar}
                    </div>
                    <div>
                      <div className="font-semibold text-gray-900">{testimonial.name}</div>
                      <div className="text-sm text-gray-600">{testimonial.role}</div>
                      <div className="text-sm text-purple-600">{testimonial.company}</div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className="py-20 bg-gradient-to-r from-purple-600 to-violet-600">
          <div className="container mx-auto px-6 text-center">
            <h2 className="text-4xl md:text-5xl font-bold text-white mb-6">
              Ready to Transform Your Inventory Management?
            </h2>
            <p className="text-xl text-purple-100 mb-12 max-w-3xl mx-auto">
              Join hundreds of businesses already using ARVO to optimize their inventory, reduce costs, and prevent stockouts.
            </p>
            
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <Button asChild size="lg" className="bg-white text-purple-600 px-8 py-4 rounded-xl text-lg font-semibold hover:shadow-2xl transform hover:scale-105 transition-all duration-300">
                <Link href="/signup">
                    Start Free 14-Day Trial
                    <ArrowRight className="w-5 h-5 ml-2" />
                </Link>
              </Button>
              <Button size="lg" variant="outline" className="border-2 border-white text-white px-8 py-4 rounded-xl text-lg font-semibold hover:bg-white hover:text-purple-600 transition-all duration-300">
                Schedule a Demo
              </Button>
            </div>
            
            <div className="mt-8 flex items-center justify-center gap-8 text-purple-100">
              <div className="flex items-center gap-2">
                <CheckCircle className="w-5 h-5" />
                <span>No credit card required</span>
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle className="w-5 h-5" />
                <span>Setup in 15 minutes</span>
              </div>
              <div className="flex items-center gap-2">
                <CheckCircle className="w-5 h-5" />
                <span>Cancel anytime</span>
              </div>
            </div>
          </div>
        </section>
      </main>

      <footer className="bg-gray-900 text-white py-16">
        <div className="container mx-auto px-6">
          <div className="grid md:grid-cols-4 gap-8">
            <div>
              <div className="flex items-center space-x-3 mb-6">
                 <InvoChatLogo className="h-8 w-8 text-primary"/>
                <span className="text-2xl font-bold">ARVO</span>
              </div>
              <p className="text-gray-400 leading-relaxed">
                AI-powered inventory intelligence that helps businesses optimize their operations and maximize profitability.
              </p>
            </div>
            
            <div>
              <h3 className="font-semibold mb-4">Product</h3>
              <ul className="space-y-2 text-gray-400">
                <li><Link href="#features" className="hover:text-white transition-colors">Features</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Integrations</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">API</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Security</Link></li>
              </ul>
            </div>
            
            <div>
              <h3 className="font-semibold mb-4">Company</h3>
              <ul className="space-y-2 text-gray-400">
                <li><Link href="#" className="hover:text-white transition-colors">About</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Blog</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Careers</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Contact</Link></li>
              </ul>
            </div>
            
            <div>
              <h3 className="font-semibold mb-4">Support</h3>
              <ul className="space-y-2 text-gray-400">
                <li><Link href="#" className="hover:text-white transition-colors">Help Center</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Documentation</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Status</Link></li>
                <li><Link href="#" className="hover:text-white transition-colors">Community</Link></li>
              </ul>
            </div>
          </div>
          
          <div className="border-t border-gray-800 mt-12 pt-8 text-center text-gray-400">
            <p>&copy; 2024 ARVO. All rights reserved.</p>
          </div>
        </div>
      </footer>
    </div>
  );
};

export { ARVOLandingPage as LandingPage };
