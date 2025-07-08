
'use client';

import { cn } from '@/lib/utils';
import type { Platform } from '../types';
import { Bot } from 'lucide-react';

function ShopifyLogo({ className }: { className?: string }) {
    return (
        <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            className={cn("text-[#78AB43]", className)}
            role="img"
            aria-label="Shopify Logo"
        >
            <path
                fill="currentColor"
                d="M19.61 8.24a2.23 2.23 0 0 0-2.2-2.24h-2.52V4.2a2.23 2.23 0 0 0-2.22-2.23h-1.32a2.24 2.24 0 0 0-2.24 2.23v1.8H6.59a2.24 2.24 0 0 0-2.23 2.24v.05l1.58 8.35a2.23 2.23 0 0 0 2.22 2.07h7.68a2.23 2.23 0 0 0 2.22-2.07l1.55-8.35v-.05Zm-8.5 0h2.52v2.52h-2.52V8.24Z"
            />
        </svg>
    );
}


function WooCommerceLogo({ className }: { className?: string }) {
    return (
        <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            className={cn("text-[#96588A]", className)}
            role="img"
            aria-label="WooCommerce Logo"
        >
           <path fillRule="evenodd" clipRule="evenodd" d="M12 2C6.477 2 2 6.477 2 12C2 17.523 6.477 22 12 22C17.523 22 22 17.523 22 12C22 6.477 17.523 2 12 2ZM9.006 8.003C9.558 8.003 10.006 8.451 10.006 9.003C10.006 9.555 9.558 10.003 9.006 10.003C8.454 10.003 8.006 9.555 8.006 9.003C8.006 8.451 8.454 8.003 9.006 8.003ZM15.006 8.003C15.558 8.003 16.006 8.451 16.006 9.003C16.006 9.555 15.558 10.003 15.006 10.003C14.454 10.003 14.006 9.555 14.006 9.003C14.006 8.451 14.454 8.003 15.006 8.003ZM7 14C7 13.448 7.448 13 8 13H16C16.552 13 17 13.448 17 14V16C17 16.552 16.552 17 16 17H8C7.448 17 7 16.552 7 16V14Z" fill="currentColor"/>
        </svg>
    );
}

function AmazonFbaLogo({ className }: { className?: string }) {
    return (
        <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            className={cn("text-[#FF9900]", className)}
            role="img"
            aria-label="Amazon Logo"
        >
            <path
                fill="currentColor"
                d="M22.13 19.34c-2 .54-4.4.24-6.24-1.04a5.62 5.62 0 0 1-2.8-5.34c0-3.1 2.5-5.63 5.56-5.63c1.37 0 2.62.47 3.65 1.32c1.03.85 1.7 2.05 1.83 3.31a1.13 1.13 0 0 1-2.26.15c-.1-.97-.56-1.85-1.27-2.5a3.42 3.42 0 0 0-2-1.28c-1.87 0-3.39 1.6-3.39 3.55c0 1.95 1.52 3.55 3.39 3.55a3.47 3.47 0 0 0 3.32-2.33a1.12 1.12 0 1 1 2.18.52c-.52 2.28-2.58 3.9-4.94 3.9c-1.2 0-2.3-.4-3.2-1.12a1.13 1.13 0 1 1 1.6-1.6c.49.43 1.1.66 1.74.66c1.1 0 2.1-.88 2.1-1.95v-1a1.12 1.12 0 0 1 1.12-1.13c.63 0 1.13.5 1.13 1.13V19a1.13 1.13 0 0 1-1.12 1.13a1.12 1.12 0 0 1-.22 0M8.56 18.2a12.87 12.87 0 0 0 8.52-3.14a.75.75 0 0 0-1-1.12A11.37 11.37 0 0 1 8.56 15.6a.75.75 0 0 0-.54 1.4a.74.74 0 0 0 .54.2m-6.4-11.45a.75.75 0 0 0-.3 1.46a18.9 18.9 0 0 1 15.86 0a.75.75 0 1 0 .3-1.46a20.4 20.4 0 0 0-15.86 0"
            />
        </svg>
    )
}

export function PlatformLogo({ platform, className }: { platform: Platform, className?: string }) {
    switch(platform) {
        case 'shopify':
            return <ShopifyLogo className={className} />;
        case 'woocommerce':
            return <WooCommerceLogo className={className} />;
        case 'amazon_fba':
             return <AmazonFbaLogo className={className} />;
        default:
            return <Bot className={className} />;
    }
}
