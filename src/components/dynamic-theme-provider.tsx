
'use client';

import { getCompanySettings } from '@/app/data-actions';
import { logger } from '@/lib/logger';
import { useEffect } from 'react';
import { useAuth } from '@/context/auth-context';

/**
 * A client component that fetches company-specific theme settings
 * and applies them as CSS variables to the root element.
 */
export function DynamicThemeProvider() {
    const { user } = useAuth();
    
    useEffect(() => {
        const applyCustomTheme = async () => {
            try {
                // This server action fetches the settings for the current user.
                const settings = await getCompanySettings();
                const root = document.documentElement;
                
                if (settings.theme_primary_color) {
                    root.style.setProperty('--primary', settings.theme_primary_color);
                }
                if (settings.theme_background_color) {
                    root.style.setProperty('--background', settings.theme_background_color);
                }
                 if (settings.theme_accent_color) {
                    root.style.setProperty('--accent', settings.theme_accent_color);
                }

            } catch (error) {
                // It's okay if this fails; the default theme will simply be used.
                // This can happen on the login page before a user session is established.
                logger.warn("[Dynamic Theme] Could not apply custom theme.", error);
            }
        };

        // Only run if there is a logged-in user.
        if (user) {
            applyCustomTheme();
        }
        
    }, [user]); // Re-run when the user logs in or out.

    // This component does not render any visible UI.
    return null;
}
