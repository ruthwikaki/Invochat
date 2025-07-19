
export default function SetupLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
          {children}
        </div>
      </body>
    </html>
  );
}
