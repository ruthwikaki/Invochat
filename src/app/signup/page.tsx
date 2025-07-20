import { AppPage, AppPageHeader } from "@/components/ui/page";
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import { Truck, RefreshCwIcon, TrendingDown, Package } from "lucide-react";
import Link from "next/link";
import { Button } from "@/components/ui/button";

const reports = [
    {
        title: "Reorder Analysis",
        description: "View AI-powered suggestions for products that need restocking.",
        href: "/analytics/reordering",
        icon: RefreshCwIcon,
    },
    {
        title: "Dead Stock",
        description: "Identify money trapped in slow-moving inventory.",
        href: "/analytics/dead-stock",
        icon: TrendingDown,
    },
    {
        title: "Supplier Performance",
        description: "Analyze which of your suppliers are the most reliable and profitable.",
        href: "/analytics/supplier-performance",
        icon: Truck,
    },
    {
        title: "Inventory Turnover",
        description: "See how efficiently your inventory is being sold and replenished.",
        href: "/analytics/inventory-turnover",
        icon: Package,
    },
];

export default function ReportsPage() {
    return (
        <AppPage>
            <AppPageHeader
                title="Analytics & Reports"
                description="Gain deeper insights into your inventory and sales performance."
            />
            <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
                {reports.map((report) => (
                    <Card key={report.href}>
                        <CardHeader>
                            <CardTitle className="flex items-center gap-2">
                                <report.icon className="h-5 w-5 text-primary" />
                                {report.title}
                            </CardTitle>
                        </CardHeader>
                        <CardContent>
                            <CardDescription>{report.description}</CardDescription>
                        </CardContent>
                        <CardFooter>
                            <Button asChild>
                                <Link href={report.href}>View Report</Link>
                            </Button>
                        </CardFooter>
                    </Card>
                ))}
            </div>
        </AppPage>
    )
}