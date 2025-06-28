
'use client';

import { useAuth } from '@/context/auth-context';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { AlertTriangle, Users, Mail } from 'lucide-react';

export default function TeamManagementPage() {
    const { user } = useAuth();

    return (
        <div className="p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                    <SidebarTrigger className="md:hidden" />
                    <div>
                        <h1 className="text-2xl font-semibold">Team Management</h1>
                        <p className="text-muted-foreground text-sm">Manage users and their roles within your company.</p>
                    </div>
                </div>
                <Button disabled>
                    <Mail className="mr-2 h-4 w-4" />
                    Invite Member
                </Button>
            </div>

            <Card>
                <CardHeader>
                    <CardTitle>Current Members</CardTitle>
                    <CardDescription>The following users have access to your company's data.</CardDescription>
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
                            {user ? (
                                <TableRow>
                                    <TableCell>
                                        <div className="flex items-center gap-3">
                                            <Avatar>
                                                <AvatarFallback>{user.email?.charAt(0).toUpperCase()}</AvatarFallback>
                                            </Avatar>
                                            <div className="font-medium">{user.email}</div>
                                        </div>
                                    </TableCell>
                                    <TableCell>
                                        <Badge>Owner</Badge>
                                    </TableCell>
                                    <TableCell className="text-right">
                                        <Button variant="outline" size="sm" disabled>Change Role</Button>
                                    </TableCell>
                                </TableRow>
                            ) : (
                                <TableRow>
                                    <TableCell colSpan={3} className="text-center text-muted-foreground">
                                        Loading user information...
                                    </TableCell>
                                </TableRow>
                            )}
                        </TableBody>
                    </Table>
                </CardContent>
            </Card>

            <Card className="bg-muted/50 border-dashed">
                <CardHeader>
                    <CardTitle className="flex items-center gap-2 text-muted-foreground">
                        <AlertTriangle className="h-5 w-5" />
                        Feature Under Development
                    </CardTitle>
                    <CardDescription>
                       Thank you for your feedback! Full team management is a top priority.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <p className="text-sm text-muted-foreground">
                        Implementing robust team management with roles, invitations, and an audit trail requires changes to the database schema. This functionality will be enabled in a future update. Here's what's planned:
                    </p>
                    <ul className="list-disc pl-5 mt-2 space-y-1 text-sm text-muted-foreground">
                        <li>Sending email invitations to new team members.</li>
                        <li>Assigning roles like "Admin," "Editor," and "Viewer."</li>
                        <li>A complete audit log to track all significant actions taken by users.</li>
                    </ul>
                </CardContent>
            </Card>
        </div>
    );
}
