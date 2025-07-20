import { LandingPage } from '@/components/landing/landing-page';

// This is the main public landing page.
// The middleware will handle redirecting authenticated users away from this page.
export default function RootPage() {
  return <LandingPage />;
}
