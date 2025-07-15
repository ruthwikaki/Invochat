
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { LogOut } from 'lucide-react';
import { useAuth } from '@/context/auth-context';
import { signOut } from '@/app/(auth)/actions';

export function UserAccountNav() {
  const { user } = useAuth();

  return (
    <div className="flex items-center gap-2 p-2">
      <Avatar className="h-8 w-8">
        <AvatarFallback>{user?.email?.charAt(0).toUpperCase() || 'U'}</AvatarFallback>
      </Avatar>
      <span className="text-sm truncate">{user?.email || 'No user found'}</span>
      <form action={signOut}>
        <Button variant="ghost" size="icon" className="h-8 w-8 ml-auto" type="submit" aria-label="Sign Out">
            <LogOut className="h-4 w-4" />
        </Button>
      </form>
    </div>
  );
}
