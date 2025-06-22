
'use server';

import { analyzeDeadStock } from '@/ai/flows/dead-stock-analysis';
import { generateChart } from '@/ai/flows/generate-chart';
import { smartReordering } from '@/ai/flows/smart-reordering';
import { getSupplierPerformance } from '@/ai/flows/supplier-performance';
import { auth } from '@/lib/firebase-server';
import type { AssistantMessagePayload } from '@/types';
import { z } from 'zod';

const actionResponseSchema = z.custom<AssistantMessagePayload>();

const UserMessagePayloadSchema = z.object({
  message: z.string(),
  idToken: z.string(),
});

type UserMessagePayload = z.infer<typeof UserMessagePayloadSchema>;

export async function handleUserMessage(
  payload: UserMessagePayload
): Promise<AssistantMessagePayload> {
  const { message, idToken } = UserMessagePayloadSchema.parse(payload);
  
  if (!auth) {
    console.error("Firebase Admin SDK is not initialized. Cannot process message. Ensure FIREBASE_SERVICE_ACCOUNT is set in your environment.");
    return {
      id: Date.now().toString(),
      role: 'assistant',
      content: "I'm sorry, but the server is not configured correctly for AI actions. Please contact support or check the server logs."
    };
  }

  let companyId: string;
  try {
    const decodedToken = await auth.verifyIdToken(idToken);
    if (!decodedToken.companyId || typeof decodedToken.companyId !== 'string') {
        throw new Error("User token is missing the required 'companyId' custom claim.");
    }
    companyId = decodedToken.companyId;
  } catch (error: any) {
    console.error("Authentication error verifying ID token:", error.message);
    return {
        id: Date.now().toString(),
        role: 'assistant',
        content: 'Authentication failed. Your session may have expired. Please log in again.'
    }
  }


  const lowerCaseMessage = message.toLowerCase();

  try {
    // Chart generation query
    if (/(chart|graph|plot|visual|draw|show me a visual)/i.test(lowerCaseMessage)) {
      const response = await generateChart({ query: message, companyId });
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
      const response = await analyzeDeadStock({ query: message, companyId });
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
      const response = await smartReordering({ query: message, companyId });
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
      const response = await getSupplierPerformance({ query: message, companyId });
      if (response && response.rankedVendors) {
        return actionResponseSchema.parse({
          id: Date.now().toString(),
          role: 'assistant',
          component: 'SupplierPerformanceTable',
          props: { data: response.rankedVendors },
        });
      }
    }
  } catch (error: any) {
    console.error('Error processing AI action:', error);
    return actionResponseSchema.parse({
      id: Date.now().toString(),
      role: 'assistant',
      content:
        `Sorry, I encountered an error while processing your request: ${error.message}. Please try again.`,
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
