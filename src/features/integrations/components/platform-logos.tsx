
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
            viewBox="0 0 512 512"
            className={cn(className)}
            role="img"
            aria-label="WooCommerce Logo"
            >
            <path
                fill="currentColor"
                d="M415.8 288.1c-1.3-4.1-3.9-7.5-7.5-9.8l-19.4-12.1c-3.1-1.9-5.1-5.4-5.1-9.2V211c0-4.1-2.2-7.8-5.8-9.8l-20.2-11.2c-3.7-2-8.2-2-11.9 0l-20.2 11.2c-3.7 2-5.8 5.8-5.8 9.8v46.1c0 3.8-2 7.3-5.1 9.2l-19.4 12.1c-3.6 2.3-6.2 5.7-7.5 9.8l-13.6 42.6c-1.8 5.6.1 11.7 4.7 15.5l19.5 16.2c3 2.5 6.9 3.9 10.8 3.9h50.5c3.9 0 7.8-1.4 10.8-3.9l19.5-16.2c4.5-3.8 6.5-9.9 4.7-15.5l-13.6-42.6zM245.2 288.1c-1.3-4.1-3.9-7.5-7.5-9.8l-19.4-12.1c-3.1-1.9-5.1-5.4-5.1-9.2V211c0-4.1-2.2-7.8-5.8-9.8l-20.2-11.2c-3.7-2-8.2-2-11.9 0l-20.2 11.2c-3.7 2-5.8 5.8-5.8 9.8v46.1c0 3.8-2 7.3-5.1 9.2l-19.4 12.1c-3.6 2.3-6.2 5.7-7.5 9.8l-13.6 42.6c-1.8 5.6.1 11.7 4.7 15.5l19.5 16.2c3 2.5 6.9 3.9 10.8 3.9h50.5c3.9 0 7.8-1.4 10.8-3.9l19.5-16.2c4.6-3.8 6.5-9.9 4.7-15.5l-13.6-42.6zM375.9 133.5l20.2-11.2c3.7-2 5.8-5.8 5.8-9.8V66.4c0-4.1-2.2-7.8-5.8-9.8l-20.2-11.2c-3.7-2-8.2-2-11.9 0l-20.2 11.2c-3.7 2-5.8 5.8-5.8 9.8v46.1c0 4.1 2.2 7.8 5.8 9.8l20.2 11.2c3.7 2.1 8.2 2.1 11.9 0z"
            />
        </svg>
    );
}

function AmazonFbaLogo({ className }: { className?: string }) {
    return (
        <svg 
            xmlns="http://www.w3.org/2000/svg" 
            viewBox="0 0 512 512"
            className={cn(className)}
            role="img"
            aria-label="Amazon Logo"
        >
            <path fill="currentColor" d="M336.4 448H175.6c-11.4 0-21.9-6-27.4-15.8L64 256.3V128h44.8l70.8 112.3 44.8-112.3H512v128.3L448 332.2c-5.5 9.8-16 15.8-27.4 15.8zM256 64C149.9 64 64 149.9 64 256s85.9 192 192 192 192-85.9 192-192S362.1 64 256 64zm164.8 320h-51.2l-64-102.4-64 102.4H87.2l116.8-185.6-112-179.2h51.2l84.8 136 84.8-136h51.2L299.2 200.8l121.6 183.2z"/>
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
