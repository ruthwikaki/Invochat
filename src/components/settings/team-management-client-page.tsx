
'use client';

import { useState, useTransition } from 'react';
import type { TeamMember } from '@/types';
import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { AlertTriangle, Mail, Loader2, Users, Edit } from 'lucide-react';
import { inviteTeamMember, removeTeamMember, updateTeamMemberRole } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../ui/select';

function ChangeRoleDialog({ member, onRoleChange, open, onOpenChange, isPending }: { member: TeamMember | null, onRoleChange: (newRole: TeamMember['role']) => void, open: boolean, onOpenChange: (open: boolean) => void, isPending: boolean }) {
    if (!member) return null;

    const [selectedRole, setSelectedRole] = useState<TeamMember['role']>(member.role);

    const handleSave = () => {
        onRoleChange(selectedRole);
    };

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Change Role for {member.email}</DialogTitle>
                    <DialogDescription>
                        Select a new role for this user. This will be saved to the database.
                    </DialogDescription>
                </DialogHeader>
                <form action={() => handleSave()} className="space-y-4 py-4">
                    <Label htmlFor="role-select">Role</Label>
                    <Select value={selectedRole} onValueChange={(value) => setSelectedRole(value as TeamMember['role'])}>
                        <SelectTrigger id="role-select" disabled={isPending}>
                            <SelectValue placeholder="Select a role" />
                        </SelectTrigger>
                        <SelectContent>
                            <SelectItem value="Member">Member (Read-only access)</SelectItem>
                            <SelectItem value="Admin">Admin (Full access, can invite users)</SelectItem>
                            <SelectItem value="Owner" disabled>Owner (Cannot be assigned)</SelectItem>
                        </SelectContent>
                    </Select>
                    <DialogFooter>
                        <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={isPending}>Cancel</Button>
                        <Button type="submit" disabled={isPending}>
                            {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            Save Changes
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}

interface TeamManagementClientPageProps {
  initialMembers: TeamMember[];
}

export function TeamManagementClientPage({ initialMembers }: TeamManagementClientPageProps) {
    const { user } = useAuth();
    const [members, setMembers] = useState<TeamMember[]>(initialMembers);
    const [invitePending, startInviteTransition] = useTransition();
    const [removePending, startRemoveTransition] = useTransition();
    const [roleChangePending, startRoleChangeTransition] = useTransition();
    const [dialogOpen, setDialogOpen] = useState(false);
    const [formError, setFormError] = useState<string | null>(null);
    const [memberToEdit, setMemberToEdit] = useState<TeamMember | null>(null);
    const [isRoleDialogOpen, setIsRoleDialogOpen] = useState(false);
    const { toast } = useToast();
    
    const currentUserRole = members.find(m => m.id === user?.id)?.role;

    const handleInvite = async (formData: FormData) => {
        setFormError(null);
        startInviteTransition(async () => {
            const result = await inviteTeamMember(formData);
            if (result.success) {
                toast({
                    title: 'Invitation Sent',
                    description: 'The user has been sent an email to join your team.',
                });
                setDialogOpen(false);
            } else {
                setFormError(result.error || 'An unknown error occurred.');
            }
        });
    };

    const handleRemoveMember = (memberId: string) => {
        startRemoveTransition(async () => {
            const result = await removeTeamMember(memberId);
            if (result.success) {
                toast({
                    title: 'Member Removed',
                    description: 'The user has been removed from your team.',
                });
                setMembers(prev => prev.filter(m => m.id !== memberId));
            } else {
                toast({
                    variant: 'destructive',
                    title: 'Error',
                    description: result.error || 'Failed to remove team member.',
                });
            }
        });
    };

    const handleOpenRoleDialog = (member: TeamMember) => {
        setMemberToEdit(member);
        setIsRoleDialogOpen(true);
    };

    const handleRoleChange = (newRole: TeamMember['role']) => {
        if (!memberToEdit) return;

        startRoleChangeTransition(async () => {
            const result = await updateTeamMemberRole(memberToEdit.id, newRole as 'Admin' | 'Member');
            if (result.success) {
                setMembers(prev => prev.map(m => m.id === memberToEdit.id ? { ...m, role: newRole } : m));
                toast({
                    title: 'Role Updated',
                    description: `${memberToEdit.email}'s role has been changed to ${newRole}.`,
                });
            } else {
                toast({
                    variant: 'destructive',
                    title: 'Error Updating Role',
                    description: result.error || 'An unknown error occurred.',
                });
            }
            setIsRoleDialogOpen(false);
            setMemberToEdit(null);
        });
    };

    const isOwner = currentUserRole === 'Owner';

    return (
        <div className="space-y-6">
             <Card>
                <CardHeader className="flex flex-row items-center justify-between">
                    <div>
                        <CardTitle>Current Members</CardTitle>
                        <CardDescription>The following users have access to your company's data.</CardDescription>
                    </div>
                     <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
                        <DialogTrigger asChild>
                            <Button disabled={!isOwner}>
                                <Mail className="mr-2 h-4 w-4" />
                                Invite Member
                            </Button>
                        </DialogTrigger>
                        <DialogContent>
                            <DialogHeader>
                                <DialogTitle>Invite a new team member</DialogTitle>
                                <DialogDescription>
                                    Enter the email of the person you want to invite. They will receive an email with instructions to join.
                                </DialogDescription>
                            </DialogHeader>
                            <form action={handleInvite} className="space-y-4">
                                <div>
                                    <Label htmlFor="email" className="sr-only">Email</Label>
                                    <Input
                                        id="email"
                                        name="email"
                                        type="email"
                                        placeholder="teammate@example.com"
                                        required
                                        disabled={invitePending}
                                    />
                                </div>
                                {formError && <p className="text-sm text-destructive">{formError}</p>}
                                <DialogFooter>
                                    <Button type="submit" disabled={invitePending}>
                                        {invitePending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                                        Send Invitation
                                    </Button>
                                </DialogFooter>
                            </form>
                        </DialogContent>
                    </Dialog>
                </CardHeader>
                <CardContent>
                    <Table>
                        <TableHeader>
                            <TableRow>
                                <TableHead>User</TableHead>
                                <TableHead>Role</TableHead>
                                <TableHead className="text-right">Actions</TableHead>
                            </TableRow>
                        </TableHeader>
                        <TableBody>
                            {members.map((member) => (
                                <TableRow key={member.id}>
                                    <TableCell>
                                        <div className="flex items-center gap-3">
                                            <Avatar>
                                                <AvatarFallback>{member.email?.charAt(0).toUpperCase()}</AvatarFallback>
                                            </Avatar>
                                            <div className="font-medium">{member.email}</div>
                                        </div>
                                    </TableCell>
                                    <TableCell>
                                        <Badge variant={member.role === 'Owner' ? 'default' : (member.role === 'Admin' ? 'secondary' : 'outline')}>{member.role}</Badge>
                                    </TableCell>
                                    <TableCell className="text-right space-x-2">
                                        <Button variant="outline" size="sm" onClick={() => handleOpenRoleDialog(member)} disabled={!isOwner || member.role === 'Owner' || removePending || roleChangePending}>
                                            <Edit className="mr-2 h-3 w-3" />
                                            Change Role
                                        </Button>
                                         <AlertDialog>
                                            <AlertDialogTrigger asChild>
                                                <Button variant="destructive" size="sm" disabled={!isOwner || member.role === 'Owner' || removePending}>
                                                    Remove
                                                </Button>
                                            </AlertDialogTrigger>
                                            <AlertDialogContent>
                                                <AlertDialogHeader>
                                                    <AlertDialogTitle>Are you absolutely sure?</AlertDialogTitle>
                                                    <AlertDialogDescription>
                                                        This action cannot be undone. This will permanently remove the user
                                                        and revoke their access to your company.
                                                    </AlertDialogDescription>
                                                </AlertDialogHeader>
                                                <AlertDialogFooter>
                                                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                                                    <AlertDialogAction onClick={() => handleRemoveMember(member.id)} disabled={removePending}>
                                                        {removePending ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : null}
                                                        Continue
                                                    </AlertDialogAction>
                                                </AlertDialogFooter>
                                            </AlertDialogContent>
                                        </AlertDialog>
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>

            <ChangeRoleDialog
                member={memberToEdit}
                onRoleChange={handleRoleChange}
                open={isRoleDialogOpen}
                onOpenChange={setIsRoleDialogOpen}
                isPending={roleChangePending}
            />

            <Card className="bg-muted/50 border-dashed">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-muted-foreground">
                        <Users className="h-5 w-5" />
                        Understanding Roles
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <ul className="list-disc pl-5 space-y-2 text-sm text-muted-foreground">
                        <li><strong>Owner:</strong> The user who created the company. Only the Owner can change roles and manage billing (feature coming soon).</li>
                        <li><strong>Admin:</strong> Can invite and remove other members, and has full access to all application features.</li>
                        <li><strong>Member:</strong> Has read-only access to most of the application. Cannot change settings or invite users.</li>
                    </ul>
                </CardContent>
            </Card>
        </div>
    );
}
