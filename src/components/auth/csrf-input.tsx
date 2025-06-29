
'use client';

import { useCsrfToken } from '@/hooks/use-csrf';
import { CSRF_FORM_NAME } from '@/lib/csrf';

export function CSRFInput() {
  const token = useCsrfToken();
  return <input type="hidden" name={CSRF_FORM_NAME} value={token || ''} />;
}
