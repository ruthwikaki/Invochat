
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export default async function HomePage() {
  const supabase = createClient();

  const { data: { user } } = await supabase.auth.getUser();

  if (user) {
    redirect('/dashboard');
  } else {
    redirect('/login');
  }

  // This component will never render anything as it always redirects.
  // Returning null is sufficient.
  return null;
}
