
import { ReactNode } from 'react';
import { SettingsNav } from './_components/settings-nav';

export default function SettingsLayout({ children }: { children: ReactNode }) {
  return (
    <div className="grid md:grid-cols-[180px_1fr] gap-6">
      <aside>
        <SettingsNav />
      </aside>
      <main>{children}</main>
    </div>
  );
}
