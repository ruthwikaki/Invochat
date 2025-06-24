
// This page is effectively disabled because the middleware at `src/middleware.ts`
// will always redirect from the root path ('/') to either '/login' or '/dashboard'.
// This component is here to satisfy Next.js's requirement for a root page,
// but it should never be rendered.
export default function HomePage() {
  return null;
}
