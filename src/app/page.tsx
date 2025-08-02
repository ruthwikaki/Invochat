import { LandingPage } from '@/components/landing/landing-page';

// The root of the app is the public-facing landing page.
// The middleware handles redirecting authenticated users to the dashboard.
export default function RootPage() {
    return <LandingPage />;
}
