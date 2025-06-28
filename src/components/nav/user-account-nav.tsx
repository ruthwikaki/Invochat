
'use client';

import { useAuth } from '@/context/auth-context';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { LogOut } from 'lucide-react';

export function UserAccountNav() {
  const { user, signOut, loading } = useAuth();

  const handleSignOut = async () => {
    await signOut();
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 p-2">
        <Skeleton className="h-8 w-8 rounded-full" />
        <Skeleton className="h-4 w-24" />
      </div>
    );
  }

  if (!user) {
    return null;
  }

  return (
    <div className="flex items-center gap-2 p-2">
      <Avatar className="h-8 w-8">
        <AvatarFallback>{user.email?.charAt(0).toUpperCase()}</AvatarFallback>
      </Avatar>
      <span className="text-sm truncate">{user.email}</span>
      <Button variant="ghost" size="icon" className="h-8 w-8 ml-auto" onClick={handleSignOut} aria-label="Sign Out">
        <LogOut className="h-4 w-4" />
      </Button>
    </div>
  );
}
