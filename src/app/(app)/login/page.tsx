import { notFound } from 'next/navigation';

// This component explicitly tells Next.js that this page should not be found.
// It uses the built-in notFound() function to prevent a route conflict with
// the actual login page at /src/app/(auth)/login/page.tsx.
export default function AppLoginPage() {
  notFound();
  // A component must return a valid element or null to be syntactically correct.
  return null;
}
