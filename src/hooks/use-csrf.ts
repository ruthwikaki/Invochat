
'use client';
import { useState, useEffect } from 'react';
import { CSRF_COOKIE_NAME } from '@/lib/csrf';
import cookie from 'cookie';

export function useCsrfToken() {
  const [token, setToken] = useState<string | null>(null);

  useEffect(() => {
    // Ensure this runs only on the client
    if (typeof window !== 'undefined') {
        const cookies = cookie.parse(document.cookie);
        setToken(cookies[CSRF_COOKIE_NAME] || null);
    }
  }, []);

  return token;
}
