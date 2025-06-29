import { notFound } from 'next/navigation';

// This component explicitly tells Next.js that this page should not be found.
// It uses the built-in notFound() function to prevent a route conflict with
// the actual login page at /src/app/(auth)/login/page.tsx.
// When this page is accessed, it will immediately trigger the not-found mechanism,
// resolving the build error.
export default function AppLoginPage() {
  notFound();
}
