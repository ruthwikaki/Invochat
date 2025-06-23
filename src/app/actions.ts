'use server';

import { supabaseAdmin } from '@/lib/supabase';
import { auth as adminAuth } from '@/lib/firebase-server';
import { analyzeDeadStock } from '@/ai/flows/dead-stock-analysis';
import { generateChart } from '@/ai/flows/generate-chart';
import { smartReordering } from '@/ai/flows/smart-reordering';
import { getSupplierPerformance } from '@/ai/flows/supplier-performance';
import { getCompanyIdForUser } from '@/services/database';
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
  
  let companyId: string;
  try {
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const firebaseUid = decodedToken.uid;
    
    const fetchedCompanyId = await getCompanyIdForUser(firebaseUid);
    if (!fetchedCompanyId) {
      throw new Error(`User profile not found in Supabase for UID: ${firebaseUid}`);
    }
    companyId = fetchedCompanyId;

  } catch (error: any) {
    console.error("Authentication or Database lookup error:", error.message);
    return {
        id: Date.now().toString(),
        role: 'assistant',
        content: 'Authentication failed. Your session may have expired or your user profile is incomplete. Please try logging in again.'
    }
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

export async function completeUserRegistration(payload: {
  companyName: string;
  email: string;
  idToken: string;
}) {
  const { companyName, email, idToken } = payload;
  try {
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const firebaseUid = decodedToken.uid;

    // 1. Create the company
    const { data: companyData, error: companyError } = await supabaseAdmin
      .from('companies')
      .insert({ name: companyName })
      .select('id')
      .single();

    if (companyError) throw companyError;
    if (!companyData) throw new Error('Failed to create company, no ID returned.');

    // 2. Create the user profile, linking it to the company
    const { error: userError } = await supabaseAdmin
      .from('users')
      .insert({
        firebase_uid: firebaseUid,
        company_id: companyData.id,
        email: email,
      });

    if (userError) throw userError;
    
    return { success: true, companyId: companyData.id };
  } catch (error: any) {
    console.error('Failed to complete user registration in database:', error);
    return {
      success: false,
      error: error.message || 'Failed to create company profile.',
    };
  }
}
