
import { AlertTriangle, Terminal } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "./ui/card";

interface MissingEnvVarsPageProps {
  errors: Record<string, string[] | undefined>;
}

export function MissingEnvVarsPage({ errors }: MissingEnvVarsPageProps) {
    const hasEncryptionKeyError = errors.ENCRYPTION_KEY || errors.ENCRYPTION_IV;

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

                    {hasEncryptionKeyError && (
                        <div className="mt-4 p-4 rounded-md border border-blue-500/20 bg-blue-500/10 text-left text-sm max-w-md w-full mx-auto text-blue-900 dark:text-blue-200">
                             <div className="flex items-center gap-2 font-bold mb-2">
                                <Terminal className="h-4 w-4" />
                                How to Generate Encryption Keys
                             </div>
                             <p className="mb-2">You can generate secure keys by running the following commands in your terminal:</p>
                             <div className="space-y-1 font-mono bg-blue-900/10 dark:bg-black/20 p-3 rounded-md">
                                <p className="text-xs text-blue-700 dark:text-blue-300"># Generate a 32-byte key (64 hex characters)</p>
                                <p className="text-blue-800 dark:text-blue-400 select-all">$ openssl rand -hex 32</p>
                                <p className="mt-2 text-xs text-blue-700 dark:text-blue-300"># Generate a 16-byte IV (32 hex characters)</p>
                                <p className="text-blue-800 dark:text-blue-400 select-all">$ openssl rand -hex 16</p>
                             </div>
                             <p className="mt-2 text-xs text-blue-800 dark:text-blue-300">Copy the output of each command and add them to your `.env` file as `ENCRYPTION_KEY` and `ENCRYPTION_IV` respectively.</p>
                        </div>
                    )}
                </CardContent>
            </Card>
        </div>
    );
}
