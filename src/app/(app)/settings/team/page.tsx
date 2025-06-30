
import { getTeamMembers } from '@/app/data-actions';
import { TeamManagementClientPage } from '@/components/settings/team-management-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function TeamManagementPage() {
    const teamMembers = await getTeamMembers();

    return (
        <AppPage>
            <AppPageHeader 
                title="Team Management"
                description="Invite and manage users for your company."
            />
            <TeamManagementClientPage initialMembers={teamMembers} />
        </AppPage>
    );
}
