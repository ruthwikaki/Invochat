
import { InvoChatLogo } from "@/components/invochat-logo";

export default function AuthLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-muted/40 p-4">
      <div className="mb-8 flex items-center gap-2 text-2xl font-semibold">
        <InvoChatLogo className="h-8 w-8" />
        <h1>InvoChat</h1>
      </div>
      <div className="w-full max-w-sm">
        {children}
      </div>
    </div>
  );
}
