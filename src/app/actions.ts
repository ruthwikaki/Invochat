'use server';

import { analyzeDeadStock } from '@/ai/flows/dead-stock-analysis';
import { generateChart } from '@/ai/flows/generate-chart';
import { smartReordering } from '@/ai/flows/smart-reordering';
import { getSupplierPerformance } from '@/ai/flows/supplier-performance';
import type { AssistantMessagePayload } from '@/types';
import { z } from 'zod';

const actionResponseSchema = z.custom<AssistantMessagePayload>();

export async function handleUserMessage(
  message: string
): Promise<AssistantMessagePayload> {
  const lowerCaseMessage = message.toLowerCase();

  try {
    // Chart generation query
    if (/(chart|graph|plot|visual|draw|show me a visual)/i.test(lowerCaseMessage)) {
      const response = await generateChart({ query: message });
      if (response) {
        return actionResponseSchema.parse({
          id: Date.now().toString(),
          role: 'assistant',
          component: 'DynamicChart',
          props: response,
        });
      }
    }

    if (
      lowerCaseMessage.includes('dead stock') ||
      lowerCaseMessage.includes('slow inventory')
    ) {
      const response = await analyzeDeadStock({ query: message });
      if (response && response.deadStockItems) {
        return actionResponseSchema.parse({
          id: Date.now().toString(),
          role: 'assistant',
          component: 'DeadStockTable',
          props: { data: response.deadStockItems },
        });
      }
    }

    if (
      lowerCaseMessage.includes('order from') ||
      lowerCaseMessage.includes('reorder')
    ) {
      const response = await smartReordering({ query: message });
      if (response && response.reorderList) {
        return actionResponseSchema.parse({
          id: Date.now().toString(),
          role: 'assistant',
          content: 'Here are the suggested items to reorder:',
          component: 'ReorderList',
          props: { items: response.reorderList },
        });
      }
    }

    if (
      lowerCaseMessage.includes('vendor') ||
      lowerCaseMessage.includes('supplier performance') ||
      lowerCaseMessage.includes('on time')
    ) {
      const response = await getSupplierPerformance({ query: message });
      if (response && response.rankedVendors) {
        return actionResponseSchema.parse({
          id: Date.now().toString(),
          role: 'assistant',
          component: 'SupplierPerformanceTable',
          props: { data: response.rankedVendors },
        });
      }
    }
  } catch (error) {
    console.error('Error processing user message:', error);
    return actionResponseSchema.parse({
      id: Date.now().toString(),
      role: 'assistant',
      content:
        'Sorry, I encountered an error while processing your request. Please try again.',
    });
  }

  // Fallback response
  return actionResponseSchema.parse({
    id: Date.now().toString(),
    role: 'assistant',
    content:
      "I'm sorry, I can't help with that. You can ask me about 'dead stock', to 'visualize warehouse distribution', or 'supplier performance'.",
  });
}
