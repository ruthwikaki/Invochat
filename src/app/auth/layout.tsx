
import { ReactNode } from 'react';

// This layout is intentionally minimal to neutralize the conflicting route.
// It ensures that any child page (which should be a redirect) can render
// without inheriting a complex or potentially broken layout.
export default function NeutralAuthLayout({ children }: { children: ReactNode }) {
  return <>{children}</>;
}
