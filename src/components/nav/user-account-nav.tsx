
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { LogOut } from 'lucide-react';
import { useRouter } from 'next/navigation';


export function UserAccountNav() {
  const router = useRouter();

  const handleSignOut = async () => {
    // This is a simplified sign out. A proper implementation
    // would call a server action to clear the Supabase session cookie.
    router.push('/login');
  };

  return (
    <div className="flex items-center gap-2 p-2">
      <Avatar className="h-8 w-8">
        <AvatarFallback>U</AvatarFallback>
      </Avatar>
      <span className="text-sm truncate">user@example.com</span>
      <Button variant="ghost" size="icon" className="h-8 w-8 ml-auto" onClick={handleSignOut} aria-label="Sign Out">
        <LogOut className="h-4 w-4" />
      </Button>
    </div>
  );
}
