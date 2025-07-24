
import { AppPageHeader } from "@/components/ui/page";
import { TeamMembersCard } from "@/app/(app)/settings/profile/_components/team-members-card";
import { CompanySettingsCard } from "./_components/company-settings-card";
import { ChannelFeesCard } from "./_components/channel-fees-card";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";

function SettingsLoading() {
    return (
        <div className="space-y-6">
            <Skeleton className="h-48 w-full" />
            <Skeleton className="h-64 w-full" />
            <Skeleton className="h-48 w-full" />
        </div>
    )
}

export default async function ProfilePage() {
    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Settings"
                description="Manage your company profile, team members, and application settings."
            />
            <Suspense fallback={<SettingsLoading />}>
                <CompanySettingsCard />
                <TeamMembersCard />
                <ChannelFeesCard />
            </Suspense>
        </div>
    )
}
