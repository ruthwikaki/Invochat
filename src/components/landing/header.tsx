'use client';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { InvoChatLogo } from '@/components/invochat-logo';
import { useState } from 'react';
import { Menu, X } from 'lucide-react';

export function LandingHeader() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  return (
    <header className="px-4 lg:px-6 h-16 flex items-center bg-background/80 backdrop-blur-md sticky top-0 z-50 border-b">
      <Link href="/" className="flex items-center justify-center gap-2" prefetch={false}>
        <InvoChatLogo className="h-8 w-8" />
        <span className="text-xl font-semibold">ARVO</span>
      </Link>
      <nav className="ml-auto hidden md:flex items-center gap-4 sm:gap-6">
        <Button asChild variant="ghost">
            <Link href="#features">Features</Link>
        </Button>
         <Button asChild variant="ghost">
            <Link href="/login">Sign In</Link>
        </Button>
        <Button asChild>
          <Link href="/signup">Sign Up</Link>
        </Button>
      </nav>
      <div className="ml-auto md:hidden">
        <Button variant="ghost" size="icon" onClick={() => setIsMenuOpen(!isMenuOpen)}>
            {isMenuOpen ? <X/> : <Menu/>}
        </Button>
      </div>
      {isMenuOpen && (
         <div className="absolute top-16 left-0 w-full bg-background/95 backdrop-blur-md md:hidden">
            <nav className="flex flex-col items-center gap-4 p-4">
                 <Button asChild variant="ghost">
                    <Link href="#features" onClick={()=>setIsMenuOpen(false)}>Features</Link>
                </Button>
                <Button asChild variant="ghost">
                    <Link href="/login" onClick={()=>setIsMenuOpen(false)}>Sign In</Link>
                </Button>
                <Button asChild>
                  <Link href="/signup" onClick={()=>setIsMenuOpen(false)}>Sign Up</Link>
                </Button>
            </nav>
        </div>
      )}
    </header>
  );
}
