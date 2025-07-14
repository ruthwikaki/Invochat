// This page is effectively disabled because the middleware at `src/middleware.ts`
// will always redirect any request to the root path ('/') to either '/login' or '/chat'.
// This component is here to satisfy Next.js's requirement for a root page,
// but it will never be rendered to the user. Its existence prevents client-side
// routing conflicts with the middleware.
export default function HomePage() {
  return null;
}
