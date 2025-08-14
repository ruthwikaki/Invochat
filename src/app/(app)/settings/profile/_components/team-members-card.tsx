
'use client';

import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from "@/components/ui/table";
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getTeamMembers, inviteTeamMember, removeTeamMember, updateTeamMemberRole } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Loader2 } from 'lucide-react';
import { getCookie, CSRF_FORM_NAME } from '@/lib/csrf-client';
import type { TeamMember } from '@/types';
import { useAuth } from '@/context/auth-context';
<<<<<<< HEAD
import { AlertSettings } from '@/components/settings/alert-settings';
=======
>>>>>>> 6168ea0773980b7de6d6d789337dd24b18126f79

const inviteSchema = z.object({
  email: z.string().email('Please enter a valid email address.'),
});

export function TeamMembersCard() {
    const queryClient = useQueryClient();
    const { toast } = useToast();
    const { user: currentUser } = useAuth();
    
    const { data: teamMembers, isLoading } = useQuery<TeamMember[]>({
        queryKey: ['teamMembers'],
        queryFn: getTeamMembers,
    });

    const { register, handleSubmit, reset, formState: { errors } } = useForm<{ email: string }>({
        resolver: zodResolver(inviteSchema),
    });

    const createFormAction = async (formData: FormData) => {
        const csrfToken = getCookie(CSRF_FORM_NAME);
        if (csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);
        return inviteTeamMember(formData);
    }
    const removeFormAction = async (formData: FormData) => {
        const csrfToken = getCookie(CSRF_FORM_NAME);
        if (csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);
        return removeTeamMember(formData);
    }
    const updateFormAction = async (formData: FormData) => {
        const csrfToken = getCookie(CSRF_FORM_NAME);
        if (csrfToken) formData.append(CSRF_FORM_NAME, csrfToken);
        return updateTeamMemberRole(formData);
    }

    const { mutate: invite, isPending: isInviting } = useMutation({
        mutationFn: createFormAction,
        onSuccess: (result) => {
            if (result.success) {
                toast({ title: "Invitation Sent", description: "The user has been invited to join your company." });
                void queryClient.invalidateQueries({ queryKey: ['teamMembers'] });
                reset();
            } else {
                toast({ variant: 'destructive', title: "Invitation Failed", description: result.error });
            }
        },
    });
    
    const { mutate: remove } = useMutation({
        mutationFn: removeFormAction,
        onSuccess: (result) => {
            if (result.success) {
                toast({ title: "Member Removed" });
                void queryClient.invalidateQueries({ queryKey: ['teamMembers']});
            } else {
                 toast({ variant: 'destructive', title: "Error", description: result.error });
            }
        }
    });

    const { mutate: updateRole } = useMutation({
        mutationFn: updateFormAction,
         onSuccess: (result) => {
            if (result.success) {
                toast({ title: "Role Updated" });
                void queryClient.invalidateQueries({ queryKey: ['teamMembers']});
            } else {
                 toast({ variant: 'destructive', title: "Error", description: result.error });
            }
        }
    });

    const onInvite = handleSubmit((data) => {
        const formData = new FormData();
        formData.append('email', data.email);
        invite(formData);
    });
    
    const currentUserRole = teamMembers?.find(m => m.id === currentUser?.id)?.role;
    const canManageTeam = currentUserRole === 'Owner' || currentUserRole === 'Admin';
    const isOwner = currentUserRole === 'Owner';
    
    return (
        <Card>
            <CardHeader>
                <CardTitle>Team Members</CardTitle>
                <CardDescription>
                    Invite and manage your team members. Only Owners and Admins can manage the team.
                </CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
                {canManageTeam && (
                     <form onSubmit={onInvite} className="flex gap-2">
                        <div className="flex-1">
                            <Input placeholder="new.member@company.com" {...register('email')} />
                            {errors.email && <p className="text-sm text-destructive pt-1">{errors.email.message}</p>}
                        </div>
                        <Button type="submit" disabled={isInviting}>
                            {isInviting && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            Send Invite
                        </Button>
                    </form>
                )}
                
                <div className="rounded-md border">
                <Table>
                    <TableHeader>
                        <TableRow>
                            <TableHead>Email</TableHead>
                            <TableHead>Role</TableHead>
                            <TableHead className="w-20"></TableHead>
                        </TableRow>
                    </TableHeader>
                    <TableBody>
                        {isLoading ? (
                            <TableRow>
                                <TableCell colSpan={3} className="text-center">
                                    <Loader2 className="mx-auto h-6 w-6 animate-spin" />
                                </TableCell>
                            </TableRow>
                        ) : (teamMembers || []).map(member => (
                            <TableRow key={member.id}>
                                <TableCell>{member.email}</TableCell>
                                <TableCell>
                                    <Select 
                                        defaultValue={member.role}
                                        onValueChange={(newRole) => {
                                            const formData = new FormData();
                                            formData.append('memberId', member.id);
                                            formData.append('newRole', newRole);
                                            updateRole(formData);
                                        }}
                                        disabled={!isOwner || member.id === currentUser?.id}
                                    >
                                        <SelectTrigger className="w-[120px] h-8">
                                            <SelectValue />
                                        </SelectTrigger>
                                        <SelectContent>
                                            <SelectItem value="Owner">Owner</SelectItem>
                                            <SelectItem value="Admin">Admin</SelectItem>
                                            <SelectItem value="Member">Member</SelectItem>
                                        </SelectContent>
                                    </Select>
                                </TableCell>
                                <TableCell>
                                    {isOwner && member.id !== currentUser?.id && (
                                        <Button variant="ghost" size="sm" onClick={() => {
                                            const formData = new FormData();
                                            formData.append('memberId', member.id);
                                            remove(formData);
                                        }}>Remove</Button>
                                    )}
                                    {currentUserRole === 'Admin' && member.role === 'Member' && (
                                        <Button variant="ghost" size="sm" onClick={() => {
                                            const formData = new FormData();
                                            formData.append('memberId', member.id);
                                            remove(formData);
                                        }}>Remove</Button>
                                    )}
                                </TableCell>
                            </TableRow>
                        ))}
                    </TableBody>
                </Table>
                </div>
            </CardContent>
        </Card>
    );
}

<<<<<<< HEAD
=======
    
>>>>>>> 6168ea0773980b7de6d6d789337dd24b18126f79
