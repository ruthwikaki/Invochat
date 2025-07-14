
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { Card, CardHeader, CardTitle, CardDescription, CardContent } from "@/components/ui/card";
import { TeamMembersCard } from "./_components/team-members-card";
import { CompanySettingsCard } from "./_components/company-settings-card";

export default function ProfilePage() {
    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Settings"
                description="Manage your company profile, team members, and application settings."
            />
            <CompanySettingsCard />
            <TeamMembersCard />
        </div>
    )
}
