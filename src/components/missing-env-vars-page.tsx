
import { AlertTriangle } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "./ui/card";

interface MissingEnvVarsPageProps {
  errors: Record<string, string[] | undefined>;
}

export function MissingEnvVarsPage({ errors }: MissingEnvVarsPageProps) {
    return (
        <div className="flex min-h-dvh flex-col items-center justify-center bg-muted/40 p-8 text-center">
            <Card className="w-full max-w-lg">
                <CardHeader>
                    <div className="mx-auto bg-destructive/10 p-4 rounded-full w-fit mb-4">
                        <AlertTriangle className="h-10 w-10 text-destructive" />
                    </div>
                    <CardTitle className="text-2xl font-bold text-destructive">Configuration Error</CardTitle>
                    <CardDescription className="mt-2 max-w-md mx-auto">
                        The application cannot start because one or more critical environment variables are missing.
                    </CardDescription>
                </CardHeader>
                <CardContent>
                    <div className="mt-2 p-4 rounded-md bg-muted text-left text-sm font-mono max-w-md w-full mx-auto">
                        <p className="font-bold mb-2">Please add the following to your `.env` file:</p>
                        <ul className="space-y-1">
                            {Object.entries(errors).map(([key, messages]) => (
                                <li key={key}>
                                    <span className="font-semibold">{key}:</span> {messages?.join(', ')}
                                </li>
                            ))}
                        </ul>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
}
