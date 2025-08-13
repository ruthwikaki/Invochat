
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function PrivacyPolicyPage() {
  return (
    <AppPage>
        <AppPageHeader
            title="Privacy Policy"
            description="Last updated: July 30, 2024"
        />
        <div className="mt-6">
            <Card>
                <CardHeader>
                    <CardTitle>Your Privacy Policy</CardTitle>
                    <CardDescription>
                        Please replace this placeholder text with the privacy policy provided by your legal service (e.g., Termly).
                    </CardDescription>
                </CardHeader>
                <CardContent className="prose dark:prose-invert max-w-none">
                    <p>
                        This is where your privacy policy content will go. It&apos;s important to detail how you collect, use, and protect your users&apos; data. Services like Termly can generate a comprehensive policy that covers legal requirements such as GDPR, CCPA, and more.
                    </p>
                    <h2>1. Information We Collect</h2>
                    <p>
                        Detail the types of personal and non-personal information you collect from users. This includes data from sign-up forms, connected integrations (e.g., Shopify, WooCommerce), and usage analytics.
                    </p>
                    <h2>2. How We Use Your Information</h2>
                    <p>
                        Explain the purposes for which you use the collected data. Examples include providing the service, improving the application, sending notifications, and personalizing the user experience with AI insights.
                    </p>
                    <h2>3. Data Sharing and Disclosure</h2>
                    <p>
                        Disclose any third-party services you share data with, such as Supabase for database hosting, Google AI for generative features, or Resend for sending emails. Be transparent about why this data is shared.
                    </p>
                    <h2>4. Your Data Rights</h2>
                    <p>
                        Inform users of their rights regarding their data, such as the right to access, correct, or delete their personal information. This is a key requirement of regulations like CCPA and GDPR.
                    </p>
                    <h2>5. Contact Us</h2>
                    <p>
                        Provide a clear way for users to contact you with any privacy-related questions or requests.
                    </p>
                </CardContent>
            </Card>
        </div>
    </AppPage>
  );
}
