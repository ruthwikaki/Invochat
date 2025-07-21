'use server';
import { LandingPage } from "@/components/landing/landing-page";

// The root of the application now shows a public landing page.
// The middleware handles redirecting authenticated users to the dashboard.
export default async function RootPage() {
    return <LandingPage />;
}
