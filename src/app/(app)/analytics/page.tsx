'use client'
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { SidebarTrigger } from "@/components/ui/sidebar"
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, LineChart, Line } from 'recharts'
import { useState, useEffect } from 'react';
import { Skeleton } from "@/components/ui/skeleton";

const turnoverData = [
  { name: 'Jan', turnover: 4 }, { name: 'Feb', turnover: 3 }, { name: 'Mar', turnover: 5 },
  { name: 'Apr', turnover: 4.5 }, { name: 'May', turnover: 4.8 }, { name: 'Jun', turnover: 5.2 },
];

const salesVelocityData = [
    { name: 'XYZ Cleaner', velocity: 120 }, { name: 'Gloves', velocity: 250 },
    { name: 'Goggles', velocity: 180 }, { name: 'Degreaser', velocity: 90 },
];


export default function AnalyticsPage() {
    const [isClient, setIsClient] = useState(false);

    useEffect(() => {
        setIsClient(true);
    }, []);

    return (
        <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <SidebarTrigger className="md:hidden" />
                <h1 className="text-2xl font-semibold">Analytics</h1>
              </div>
            </div>

            <div className="grid gap-6 md:grid-cols-2">
                <Card>
                    <CardHeader>
                        <CardTitle>Inventory Turnover Ratio</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <div className="h-[300px]">
                            {isClient ? (
                                <ResponsiveContainer width="100%" height="100%">
                                    <LineChart data={turnoverData}>
                                        <CartesianGrid strokeDasharray="3 3" />
                                        <XAxis dataKey="name" />
                                        <YAxis />
                                        <Tooltip />
                                        <Legend />
                                        <Line type="monotone" dataKey="turnover" stroke="hsl(var(--primary))" activeDot={{ r: 8 }} />
                                    </LineChart>
                                </ResponsiveContainer>
                            ) : (
                                <Skeleton className="h-full w-full" />
                            )}
                        </div>
                    </CardContent>
                </Card>
                <Card>
                    <CardHeader>
                        <CardTitle>Sales Velocity (Units/Month)</CardTitle>
                    </CardHeader>
                    <CardContent>
                         <div className="h-[300px]">
                            {isClient ? (
                                <ResponsiveContainer width="100%" height="100%">
                                    <BarChart data={salesVelocityData}>
                                        <CartesianGrid strokeDasharray="3 3" />
                                        <XAxis dataKey="name" />
                                        <YAxis />
                                        <Tooltip />
                                        <Legend />
                                        <Bar dataKey="velocity" fill="hsl(var(--primary))" />
                                    </BarChart>
                                </ResponsiveContainer>
                            ) : (
                                <Skeleton className="h-full w-full" />
                            )}
                        </div>
                    </CardContent>
                </Card>
            </div>
            <Card>
                <CardHeader>
                    <CardTitle>Coming Soon</CardTitle>
                </CardHeader>
                <CardContent>
                    <div className="h-60 flex items-center justify-center text-muted-foreground">
                        More advanced analytics and trend visualizations are on the way!
                    </div>
                </CardContent>
            </Card>
        </div>
    )
}
