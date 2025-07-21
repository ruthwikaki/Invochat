import { getCompanySettings } from "@/app/data-actions"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { CompanySettingsForm } from "./company-settings-form"

export async function CompanySettingsCard() {
    const settings = await getCompanySettings();

    return (
        <Card>
            <CardHeader>
                <CardTitle>Business Logic Settings</CardTitle>
                <CardDescription>
                    Adjust the parameters used for AI analysis and suggestions.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <CompanySettingsForm settings={settings} />
            </CardContent>
        </Card>
    )
}
