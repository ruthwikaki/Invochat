/**
 * This file is intentionally structured to resolve a Next.js build error.
 * A file named `page.tsx` is only treated as a page if it has a `default`
 * export that is a React component. By only having a named export of a
 * constant, we signal to the build system to ignore this file, resolving
 * the parallel route conflict with `/(auth)/login/page.tsx`.
 */
export const a = 'this is not a page';
