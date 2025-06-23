'use server';

import { supabaseAdmin } from '@/lib/supabase';
import { auth as adminAuth } from '@/lib/firebase-server';
import { analyzeDeadStock } from '@/ai/flows/dead-stock-analysis';
import { generateChart } from '@/ai/flows/generate-chart';
import { smartReordering } from '@/ai/flows/smart-reordering';
import { getSupplierPerformance } from '@/ai/flows/supplier-performance';
import { getCompanyIdForUser } from '@/services/database';
import type { AssistantMessagePayload, UserProfile } from '@/types';
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


const setupCompanyPayloadSchema = z.object({
  idToken: z.string(),
  companyChoice: z.enum(['create', 'join']),
  companyNameOrCode: z.string().min(1),
});

type SetupCompanyPayload = z.infer<typeof setupCompanyPayloadSchema>;

function generateInviteCode() {
    return Math.random().toString(36).substring(2, 8).toUpperCase();
}


export async function setupCompanyAndUserProfile(payload: SetupCompanyPayload): Promise<{ success: boolean, error?: string, profile?: UserProfile }> {
    const { idToken, companyChoice, companyNameOrCode } = setupCompanyPayloadSchema.parse(payload);

    let decodedToken;
    try {
        decodedToken = await adminAuth.verifyIdToken(idToken);
    } catch (error) {
        console.error("Invalid ID token:", error);
        return { success: false, error: 'Authentication failed. Please sign in again.' };
    }

    const { uid: firebase_uid, email } = decodedToken;
    if (!email) {
        return { success: false, error: 'User email is not available.' };
    }

    let companyId;
    let userRole: 'admin' | 'member' = 'member';

    try {
        if (companyChoice === 'create') {
            const companyName = companyNameOrCode;
            const inviteCode = generateInviteCode();
            
            const { data: companyData, error: companyError } = await supabaseAdmin
                .from('companies')
                .insert({ name: companyName, invite_code: inviteCode, created_by: firebase_uid })
                .select('id')
                .single();

            if (companyError) throw new Error(`Failed to create company: ${companyError.message}`);
            
            companyId = companyData.id;
            userRole = 'admin';

        } else { // 'join'
            const inviteCode = companyNameOrCode;
            const { data: companyData, error: companyError } = await supabaseAdmin
                .from('companies')
                .select('id')
                .eq('invite_code', inviteCode)
                .single();
            
            if (companyError || !companyData) {
                return { success: false, error: 'Invalid invite code. Please check and try again.' };
            }

            companyId = companyData.id;
            userRole = 'member';
        }

        // Now create the user profile
        const { data: userProfile, error: userError } = await supabaseAdmin
            .from('users')
            .insert({
                firebase_uid,
                email,
                company_id: companyId,
                role: userRole,
            })
            .select(`
                *,
                company:companies(*)
            `)
            .single();
        
        if (userError) {
             if (userError.code === '23505') { // unique_violation
                return { success: false, error: 'This user profile already exists.' };
            }
            throw new Error(`Failed to create user profile: ${userError.message}`);
        }

        return { success: true, profile: userProfile as UserProfile };

    } catch (error: any) {
        console.error('Error in setupCompanyAndUserProfile:', error);
        return { success: false, error: error.message || 'An unexpected error occurred.' };
    }
}
