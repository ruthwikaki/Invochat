
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { LogOut } from 'lucide-react';
import { signOut } from '@/app/(auth)/actions';

export function UserAccountNav({ userEmail }: { userEmail: string | null }) {
  return (
    <form action={signOut} className="w-full">
      <div className="flex items-center gap-2 p-2">
        <Avatar className="h-8 w-8">
          <AvatarFallback>{userEmail?.charAt(0).toUpperCase() || 'U'}</AvatarFallback>
        </Avatar>
        <span className="text-sm truncate flex-1">{userEmail || 'No user found'}</span>
        <Button
          type="submit"
          variant="ghost"
          size="icon"
          className="h-8 w-8 ml-auto"
          aria-label="Sign Out"
        >
          <LogOut className="h-4 w-4" />
        </Button>
      </div>
    </form>
  );
}
