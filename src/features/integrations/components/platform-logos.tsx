
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
            viewBox="0 0 256 256"
            className={cn("text-[#96588A]", className)}
            role="img"
            aria-label="WooCommerce Logo"
        >
            <path
                fill="currentColor"
                d="M185.73,61.73,168,44,128,84,88,44,70.27,61.73,110.2,102H72v24h56l-40,40H72v24h56l-40,40H72v24h56l39.8-39.8L224,102H185.73Z"
                transform="translate(-40 -40)"
            />
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
                d="M16.36,13.52a6.74,6.74,0,0,1-3.6,1.11c-2.49,0-4.32-1.81-4.32-4.15,0-2.38,1.79-4.22,4.2-4.22a5.4,5.4,0,0,1,3.47,1.2L14.7,8.81a3,3,0,0,0-2-1.11,2.12,2.12,0,0,0-2.19,2.27,2.1,2.1,0,0,0,2.16,2.18,3.16,3.16,0,0,0,1.82-.55v-1H12.82V9.13h3.54Zm2.12,4.19a12.87,12.87,0,0,0,8.52-3.14.75.75,0,0,0-1-1.12A11.37,11.37,0,0,1,8.56,15.6a.75.75,0,0,0-.54,1.4.74.74,0,0,0,.54.2m-6.4-11.45a.75.75,0,0,0-.3,1.46,18.9,18.9,0,0,1,15.86,0,.75.75,0,1,0,.3-1.46,20.4,20.4,0,0,0-15.86,0"
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
