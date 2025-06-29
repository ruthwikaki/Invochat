import { notFound } from 'next/navigation';

// This component explicitly tells Next.js that this page should not be found.
// It uses the built-in notFound() function to prevent a route conflict with
// the actual login page at /src/app/(auth)/login/page.tsx.
// A component must return a valid element or null, so we add `return null`
// after `notFound()` to make this a valid component definition.
export default function AppLoginPage() {
  notFound();
  return null;
}
