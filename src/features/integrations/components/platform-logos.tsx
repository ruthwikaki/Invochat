
'use client';

import { cn } from '@/lib/utils';
import type { Platform } from '../types';
import { Bot } from 'lucide-react';

function ShopifyLogo({ className }: { className?: string }) {
    return (
         <div 
            className={cn("bg-contain bg-center bg-no-repeat", className)}
            style={{ backgroundImage: `url('https://cdn.shopify.com/shopify-marketing_assets/static/shopify-favicon.png')`}}
            role="img"
            aria-label="Shopify Logo"
        />
    )
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
             <path
                fill="currentColor"
                d="M5.46 15.22s.34.09.77-.18c.44-.27.44-.69.44-.69s-.08-.52-.51-.26c-.44.26-1.03.4-1.03.4l.33.73zm1.87-3.4s.48.25.98.02c.5-.23.63-.7.63-.7s-.14-.58-.72-.34c-.58.23-1.12.5-1.12.5l.23.52zm1.6-3.32s.56.33.98.22c.42-.11.52-.5.52-.5s-.2-.53-.74-.4c-.54.12-1.08.34-1.08.34l.32.34zm2.14-2.8s.5-.06.77-.38c.27-.32.23-.68.23-.68s-.3-.38-.72-.1c-.41.28-.7.4-.7.4l.42.76zM7.18 19.34c.3-.13.56-.26.56-.26l-1.6-3.66s-1.03.4-1.35.53c-.31.13-.5.22-.5.22s.33.76.68.96c.36.2.8.34.8.34l1.41-1.8v3.66l-.02.01zM4.33 4.5l-.26.57L2.2 14.2s.63.29 1.35.58l.09-.2L5.8 5.25s-.6-.23-1.06-.5c-.45-.27-.4-.25-.4-.25zm11.26 1.34c.3-.13.56-.26.56-.26l-1.6-3.66s-1.03.4-1.35.53c-.31.13-.5.22-.5.22s.33.76.68.96c.36.2.8.34.8.34l1.41-1.8v3.66l-.02.01zM12.98 4.5l-.26.57L10.84 14.2s.63.29 1.35.58l.09-.2L14.43 5.25s-.6-.23-1.06-.5c-.45-.27-.4-.25-.4-.25zm5.58 1.34c.3-.13.56-.26.56-.26l-1.6-3.66s-1.03.4-1.35.53c-.31.13-.5.22-.5.22s.33.76.68.96c.36.2.8.34.8.34l1.41-1.8v3.66l-.02.01zM18.57 4.5l-.26.57L16.44 14.2s.63.29 1.35.58l.09-.2L20.03 5.25s-.6-.23-1.06-.5c-.45-.27-.4-.25-.4-.25z"
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
                d="M16.92 17.38a9.38 9.38 0 0 1-9.84 0L.3 12.7a1 1 0 0 1 .4-1.38L16.92.6a1 1 0 0 1 1.18 1.58l-3.3 4.2a1 1 0 0 0 .2 1.38l6.1 3.8a1 1 0 0 1 .4 1.38l-4.58 4.44zm-1.6-5.4a1 1 0 0 0-1-1.72H1.72a1 1 0 1 0 0 2h12.6a1 1 0 0 0 1-1.72l-1-1.44z"
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
