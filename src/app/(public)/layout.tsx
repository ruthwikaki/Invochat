
import { LandingHeader } from '@/components/landing/header';

export default function PublicLayout({
    children,
}: {
    children: React.ReactNode;
}) {
    return (
        <div className="flex min-h-dvh flex-col bg-gray-50 text-gray-800">
            <LandingHeader />
            <main className="flex-1">{children}</main>
        </div>
    )
}
