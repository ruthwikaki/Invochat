// Since middleware handles the redirect, this page should never be reached
// but we'll provide a loading state just in case
export default function RootPage() {
  return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-gray-900"></div>
    </div>
  );
}
