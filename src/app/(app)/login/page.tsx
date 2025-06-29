import { notFound } from 'next/navigation';

/**
 * This component exists to resolve a build-time route conflict.
 * The application has a primary login page at `/(auth)/login/page.tsx`.
 * This file at `/(app)/login/page.tsx` creates a parallel route to the same `/login` path,
 * which causes a Next.js build error.
 *
 * To solve this, we remove the `default` export. A Next.js page component
 * MUST be a default export. By making this a named export, we signal to the
 * build system that this is not a page, resolving the conflict.
 * The notFound() call is kept as a safeguard in case this component were ever
 * to be rendered, ensuring it serves a 404 page.
 */
export function ConflictingLoginPage() {
  notFound();
  return null;
}
