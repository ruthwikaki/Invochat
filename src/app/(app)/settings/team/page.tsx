
import { SidebarTrigger } from '@/components/ui/sidebar';
import { getTeamMembers } from '@/app/data-actions';
import { TeamManagementClientPage } from '@/components/settings/team-management-client-page';

export default async function TeamManagementPage() {
    const teamMembers = await getTeamMembers();

    return (
        <div className="p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <div>
                        <h1 className="text-2xl font-semibold">Team Management</h1>
                        <p className="text-muted-foreground text-sm">Invite and manage users for your company.</p>
                    </div>
                </div>
            </div>

            <TeamManagementClientPage initialMembers={teamMembers} />
        </div>
    );
}
