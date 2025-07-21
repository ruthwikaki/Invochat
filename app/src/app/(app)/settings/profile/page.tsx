
import { AppPageHeader } from "@/components/ui/page";
import { TeamMembersCard } from "./_components/team-members-card";
import { CompanySettingsCard } from "../_components/company-settings-card";
import { ChannelFeesCard } from "../_components/channel-fees-card";
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export default async function ProfilePage() {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get(name: string) {
              return cookieStore.get(name)?.value
            },
          },
        }
    );
    const { data: { user } } = await supabase.auth.getUser();

    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Settings"
                description="Manage your company profile, team members, and application settings."
            />
            <CompanySettingsCard />
            <ChannelFeesCard />
            <TeamMembersCard currentUserId={user?.id || null} />
        </div>
    )
}
