
'use server';
import { config } from 'dotenv';
config();

import '@/ai/flows/universal-chat.ts';
import '@/ai/flows/reorder-tool.ts';
import '@/ai/flows/supplier-performance-tool.ts';
import '@/ai/flows/create-po-tool.ts';
import '@/ai/flows/economic-tool.ts';
import '@/ai/flows/dead-stock-tool.ts';
import '@/ai/flows/inventory-turnover-tool.ts';
import '@/ai/flows/insights-summary-flow.ts';
import '@/ai/flows/analytics-tools.ts';
