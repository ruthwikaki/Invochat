export default function QuickTest() {
  const hasUrl = !!process.env.NEXT_PUBLIC_SUPABASE_URL;
  const hasKey = !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  
  return (
    <div className="p-8">
      <h1>Quick Environment Test</h1>
      <p>URL: {hasUrl ? '✅' : '❌'}</p>
      <p>Key: {hasKey ? '✅' : '❌'}</p>
      <p>URL Value: {process.env.NEXT_PUBLIC_SUPABASE_URL}</p>
    </div>
  );
}
