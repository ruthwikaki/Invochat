import { InvoChatLogo } from '@/components/invochat-logo';

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900">
      <div className="max-w-md w-full space-y-8 p-4">
        <div className="text-center">
          <InvoChatLogo className="mx-auto h-12 w-auto" />
          <h1 className="mt-4 text-3xl font-bold text-gray-900 dark:text-white">
            ARVO
          </h1>
          <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Conversational Inventory Intelligence
          </p>
        </div>
        {children}
      </div>
    </div>
  );
}
