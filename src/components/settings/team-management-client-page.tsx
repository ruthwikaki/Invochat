
'use client';

import { useState, useTransition } from 'react';
import type { TeamMember } from '@/types';
import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { AlertTriangle, Mail, Loader2, Users } from 'lucide-react';
import { inviteTeamMember } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';

interface TeamManagementClientPageProps {
  initialMembers: TeamMember[];
}

export function TeamManagementClientPage({ initialMembers }: TeamManagementClientPageProps) {
    const { user } = useAuth();
    const [members, setMembers] = useState<TeamMember[]>(initialMembers);
    const [isPending, startTransition] = useTransition();
    const [dialogOpen, setDialogOpen] = useState(false);
    const [formError, setFormError] = useState<string | null>(null);
    const { toast } = useToast();

    const handleInvite = async (formData: FormData) => {
        setFormError(null);
        startTransition(async () => {
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
                            <Button>
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
                                        disabled={isPending}
                                    />
                                </div>
                                {formError && <p className="text-sm text-destructive">{formError}</p>}
                                <DialogFooter>
                                    <Button type="submit" disabled={isPending}>
                                        {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
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
                                        <Badge variant={member.role === 'Owner' ? 'default' : 'secondary'}>{member.role}</Badge>
                                    </TableCell>
                                    <TableCell className="text-right space-x-2">
                                        <Button variant="outline" size="sm" disabled>Change Role</Button>
                                        <Button variant="destructive" size="sm" disabled>Remove</Button>
                                    </TableCell>
                                </TableRow>
                            ))}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>

            <Card className="bg-muted/50 border-dashed">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-muted-foreground">
                        <AlertTriangle className="h-5 w-5" />
                        Advanced Features Coming Soon
                    </CardTitle>
                </CardHeader>
                <CardContent>
                    <p className="text-sm text-muted-foreground">
                        Full team management is a top priority. Here's what's planned for future updates, which will require changes to the database schema:
                    </p>
                    <ul className="list-disc pl-5 mt-2 space-y-1 text-sm text-muted-foreground">
                        <li>**Role-Based Access Control:** Assigning fine-grained permissions like "Admin," "Editor," and "Viewer."</li>
                        <li>**User Management:** The ability to change user roles or remove them from the team.</li>
                        <li>**Audit Logs:** A complete log to track all significant actions taken by users for security and accountability.</li>
                    </ul>
                </CardContent>
            </Card>
        </div>
    );
}
