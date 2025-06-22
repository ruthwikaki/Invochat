'use client';
import { useAuth } from "@/context/auth-context";
import { useRouter } from "next/navigation";
import { useEffect } from "react";

export default function Home() {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    // Wait until the authentication state is determined.
    if (!loading) {
      if (user) {
        // If the user is logged in, redirect them to the dashboard.
        router.replace('/dashboard');
      } else {
        // If the user is not logged in, redirect them to the login page.
        router.replace('/login');
      }
    }
  }, [user, loading, router]);
  
  // This page's only job is to redirect. It should not render any content.
  // Returning null is the standard practice for this "bouncer" pattern.
  return null;
}
