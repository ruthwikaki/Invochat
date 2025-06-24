
'use server';

import { analyzeDeadStock } from '@/ai/flows/dead-stock-analysis';
import { generateChart } from '@/ai/flows/generate-chart';
import { smartReordering } from '@/ai/flows/smart-reordering';
import { getSupplierPerformance } from '@/ai/flows/supplier-performance';
import type { AssistantMessagePayload } from '@/types';
import { createClient } from '@/lib/supabase/server';
import { z } from 'zod';
import { cookies } from 'next/headers';

const actionResponseSchema = z.custom<AssistantMessagePayload>();

const UserMessagePayloadSchema = z.object({
  message: z.string(),
});

type UserMessagePayload = z.infer<typeof UserMessagePayloadSchema>;


async function getCompanyIdForCurrentUser(): Promise<string> {
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
        throw new Error("User not found. Please log in again.");
    }

    // The company_id is stored in the user's app_metadata (JWT claim).
    // This is the fastest, most reliable source once the session is established.
    const companyIdFromClaim = user.app_metadata?.company_id;
    if (companyIdFromClaim && typeof companyIdFromClaim === 'string') {
        return companyIdFromClaim;
    }

    // Fallback for race condition: If the claim isn't populated yet (e.g., right after signup),
    // we query the database directly. This provides a more immediate source of truth.
    const { data: profile } = await supabase
        .from('users')
        .select('company_id')
        .eq('id', user.id)
        .single();
        
    const companyIdFromDb = profile?.company_id;
    if (companyIdFromDb) {
        return companyIdFromDb;
    }

    // This is a critical error state.
    console.error(`User ${user.id} is missing a valid company_id in both JWT claims and the users table.`);
    throw new Error("I couldn't verify your company information. Please try logging out and in again.");
}


export async function handleUserMessage(
  payload: UserMessagePayload
): Promise<AssistantMessagePayload> {
  const { message } = UserMessagePayloadSchema.parse(payload);
  
  let companyId: string;
  try {
    companyId = await getCompanyIdForCurrentUser();
  } catch(error: any) {
     return actionResponseSchema.parse({
        id: Date.now().toString(),
        role: 'assistant',
        content: error.message,
    });
  }

  const lowerCaseMessage = message.toLowerCase();

  try {
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
      if (response && response.vendors) {
        return actionResponseSchema.parse({
          id: Date.now().toString(),
          role: 'assistant',
          component: 'SupplierPerformanceTable',
          props: { data: response.vendors },
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
