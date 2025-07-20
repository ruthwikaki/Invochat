
import { LandingPage } from '@/components/landing/landing-page';

// This is the public landing page.
// The middleware will handle redirecting authenticated users to the dashboard.
export default function PublicHomePage() {
    return <LandingPage />;
}
