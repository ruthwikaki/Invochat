
'use client';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { InvoChatLogo } from '@/components/invochat-logo';
import { useState, useEffect } from 'react';
import { Menu, X } from 'lucide-react';

export function LandingHeader() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isScrolled, setIsScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 10);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <header
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        isScrolled ? 'bg-white/80 backdrop-blur-lg shadow-md' : 'bg-transparent'
      }`}
    >
      <div className="container mx-auto px-4 lg:px-6 h-20 flex items-center justify-between">
        <Link href="/" className="flex items-center justify-center gap-2" prefetch={false}>
          <InvoChatLogo className="h-8 w-8 text-primary" />
          <span className="text-xl font-semibold text-gray-800">ARVO</span>
        </Link>
        <nav className="ml-auto hidden md:flex items-center gap-4 sm:gap-6">
          <Button asChild variant="ghost">
            <Link href="#features" className="text-gray-600 hover:text-primary">Features</Link>
          </Button>
           <Button asChild variant="ghost">
            <Link href="/login" className="text-gray-600 hover:text-primary">Sign In</Link>
          </Button>
          <Button asChild className="bg-primary hover:bg-primary/90 text-white rounded-full px-6 py-2 shadow-lg hover:shadow-xl transition-shadow">
            <Link href="/signup">Sign Up Free</Link>
          </Button>
        </nav>
        <div className="ml-auto md:hidden">
          <Button variant="ghost" size="icon" onClick={() => setIsMenuOpen(!isMenuOpen)}>
            {isMenuOpen ? <X className="text-gray-800" /> : <Menu className="text-gray-800" />}
          </Button>
        </div>
      </div>
      {isMenuOpen && (
        <div className="absolute top-20 left-0 w-full bg-white shadow-lg md:hidden">
          <nav className="flex flex-col items-center gap-4 p-4">
            <Button asChild variant="ghost" className="w-full">
              <Link href="#features" onClick={() => setIsMenuOpen(false)}>Features</Link>
            </Button>
            <Button asChild variant="ghost" className="w-full">
              <Link href="/login" onClick={() => setIsMenuOpen(false)}>Sign In</Link>
            </Button>
            <Button asChild className="w-full">
              <Link href="/signup" onClick={() => setIsMenuOpen(false)}>Sign Up Free</Link>
            </Button>
          </nav>
        </div>
      )}
    </header>
  );
}
