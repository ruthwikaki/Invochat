
'use client';
import { useState, useEffect } from 'react';
import { CSRF_COOKIE_NAME } from '@/lib/csrf';

export function useCsrfToken() {
  const [token, setToken] = useState<string | null>(null);

  useEffect(() => {
    // This effect runs only on the client after the component mounts.
    // By this time, the browser should have processed all Set-Cookie headers from the server response.
    if (typeof document !== 'undefined') {
      const cookies = document.cookie.split(';');
      for (let i = 0; i < cookies.length; i++) {
        let cookie = cookies[i].trim();
        // Does this cookie string begin with the name we want?
        if (cookie.startsWith(CSRF_COOKIE_NAME + '=')) {
          setToken(cookie.substring(CSRF_COOKIE_NAME.length + 1));
          return; // Exit loop once found
        }
      }
    }
  }, []);

  return token;
}
