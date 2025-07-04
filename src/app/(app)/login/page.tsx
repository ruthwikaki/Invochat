// This file is intentionally left almost blank to prevent a routing conflict.
// The presence of a `page.tsx` file in this directory would create a `/login` route,
// which conflicts with the primary login page at `/src/app/(auth)/login/page.tsx`.
// By not exporting a default React component, we prevent Next.js from treating this file as a page.
export {};
