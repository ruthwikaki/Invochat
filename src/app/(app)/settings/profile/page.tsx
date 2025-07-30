
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { TeamMembersCard } from "@/app/(app)/settings/profile/_components/team-members-card";
import { CompanySettingsCard } from "./_components/company-settings-card";
import { ChannelFeesCard } from "./_components/channel-fees-card";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { AlertSettings } from "@/components/settings/alert-settings";

function SettingsLoading() {
    return (
        <div className="space-y-6">
            <Skeleton className="h-48 w-full" />
            <Skeleton className="h-64 w-full" />
            <Skeleton className="h-48 w-full" />
        </div>
    )
}

export default function ProfilePage() {
    return (
        <AppPage>
            <AppPageHeader
                title="Settings"
                description="Manage your company profile, team members, and application settings."
            />
            <div className="space-y-6 mt-6">
                <Suspense fallback={<SettingsLoading />}>
                    <CompanySettingsCard />
                    <AlertSettings />
                    <TeamMembersCard />
                    <ChannelFeesCard />
                </Suspense>
            </div>
        </AppPage>
    )
}
