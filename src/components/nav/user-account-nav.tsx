
'use client';

import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { LogOut } from 'lucide-react';
import { useAuth } from '@/context/auth-context';
import { useRouter } from 'next/navigation';

export function UserAccountNav() {
  const { user, logout } = useAuth();
  const router = useRouter();

  const handleLogout = async () => {
    await logout();
    router.push('/login');
    router.refresh();
  }

  return (
    <div className="flex items-center gap-2 p-2">
      <Avatar className="h-8 w-8">
        <AvatarFallback>{user?.email?.charAt(0).toUpperCase() || 'U'}</AvatarFallback>
      </Avatar>
      <span className="text-sm truncate">{user?.email || 'No user found'}</span>
      <Button variant="ghost" size="icon" className="h-8 w-8 ml-auto" onClick={handleLogout} aria-label="Sign Out">
          <LogOut className="h-4 w-4" />
      </Button>
    </div>
  );
}
