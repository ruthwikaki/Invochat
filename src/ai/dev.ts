import { config } from 'dotenv';
config();

import '@/ai/flows/smart-reordering.ts';
import '@/ai/flows/supplier-performance.ts';
import '@/ai/flows/dead-stock-analysis.ts';
import '@/ai/flows/generate-chart.ts';
