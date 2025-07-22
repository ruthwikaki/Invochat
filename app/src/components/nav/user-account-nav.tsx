
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { LogOut } from 'lucide-react';
import { useAuth } from '@/context/auth-context';
import type { User } from '@/types';

export function UserAccountNav({user}: {user: User | null}) {
  const { logout } = useAuth();

  return (
      <div className="flex items-center gap-2 p-2">
        <Avatar className="h-8 w-8">
          <AvatarFallback>{user?.email?.charAt(0).toUpperCase() || 'U'}</AvatarFallback>
        </Avatar>
        <span className="text-sm truncate flex-1">{user?.email || 'No user found'}</span>
        <Button
            type="button"
            variant="ghost"
            size="icon"
            className="h-8 w-8 ml-auto"
            aria-label="Sign Out"
            onClick={() => logout()}
        >
            <LogOut className="h-4 w-4" />
        </Button>
      </div>
  );
}
