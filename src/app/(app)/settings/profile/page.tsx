
import { AppPageHeader } from "@/components/ui/page";
import { TeamMembersCard } from "@/app/(app)/settings/profile/_components/team-members-card";
import { CompanySettingsCard } from "./_components/company-settings-card";
import { ChannelFeesCard } from "./_components/channel-fees-card";

export default async function ProfilePage() {
    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Settings"
                description="Manage your company profile, team members, and application settings."
            />
            <CompanySettingsCard />
            <TeamMembersCard />
            <ChannelFeesCard />
        </div>
    )
}
