
'use server';
import { config } from 'dotenv';
config();

import '@/ai/flows/universal-chat.ts';
import '@/ai/flows/reorder-tool.ts';
import '@/ai/flows/supplier-performance-tool.ts';
import '@/ai/flows/analyze-supplier-flow.ts';
import '@/ai/flows/economic-tool.ts';
import '@/ai/flows/dead-stock-tool.ts';
import '@/ai/flows/inventory-turnover-tool.ts';
import '@/ai/flows/insights-summary-flow.ts';
import '@/ai/flows/analytics-tools.ts';
import '@/ai/flows/anomaly-explanation-flow.ts';
import '@/ai/flows/csv-mapping-flow.ts';
import '@/ai/flows/suggest-bundles-flow.ts';
import '@/ai/flows/price-optimization-flow.ts';
import '@/ai/flows/markdown-optimizer-flow.ts';
import '@/ai/flows/hidden-money-finder-flow.ts';
import '@/ai/flows/morning-briefing-flow.ts';
import '@/ai/flows/alert-explanation-flow.ts';
import '@/ai/flows/generate-description-flow.ts';
import '@/ai/flows/customer-insights-flow.ts';
import '@/ai/flows/product-demand-forecast-flow.ts';
