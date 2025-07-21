
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { InvoChatLogo } from '@/components/invochat-logo';

export function LandingHeader() {
  return (
    <header className="px-4 lg:px-6 h-16 flex items-center bg-background/80 backdrop-blur-md sticky top-0 z-50 border-b">
      <Link href="/" className="flex items-center justify-center gap-2" prefetch={false}>
        <InvoChatLogo className="h-8 w-8" />
        <span className="text-xl font-semibold">ARVO</span>
      </Link>
      <nav className="ml-auto flex items-center gap-4 sm:gap-6">
        <Button asChild variant="ghost">
            <Link href="/login">Sign In</Link>
        </Button>
        <Button asChild>
          <Link href="/signup">Sign Up</Link>
        </Button>
      </nav>
    </header>
  );
}
