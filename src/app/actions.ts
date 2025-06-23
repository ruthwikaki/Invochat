
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

export async function getUserProfile(idToken: string): Promise<UserProfile | null> {
  if (!adminAuth) {
    throw new Error('Firebase Admin SDK not initialized');
  }

  if (!supabaseAdmin) {
    throw new Error('Supabase Admin client not initialized');
  }

  try {
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const userId = decodedToken.uid;
    
    // Standardized lookup on `users` table and `firebase_uid` column
    const { data: profile, error } = await supabaseAdmin
      .from('users')
      .select(`
        firebase_uid,
        email,
        role,
        company_id,
        companies (
          id,
          name
        )
      `)
      .eq('firebase_uid', userId)
      .single();

    if (error || !profile) {
      console.warn('Profile fetch warning:', error?.message);
      return null;
    }
    
    return {
      id: profile.firebase_uid,
      email: profile.email,
      role: profile.role,
      companyId: profile.company_id,
      company: profile.companies ? {
        id: profile.companies.id,
        name: profile.companies.name,
      } : undefined
    };
  } catch (error) {
    console.error('Error getting user profile:', error);
    return null;
  }
}

export async function setupCompanyAndUserProfile({
  idToken,
  companyChoice,
  companyNameOrCode,
}: {
  idToken: string;
  companyChoice: 'create' | 'join';
  companyNameOrCode: string;
}): Promise<{ success: boolean; error?: string; profile?: UserProfile }> {
  if (!adminAuth || !supabaseAdmin) {
    return { success: false, error: 'Server not configured.' };
  }

  try {
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const userId = decodedToken.uid;
    const userEmail = decodedToken.email;

    if (!userEmail) {
      return { success: false, error: 'User email not found in token.' };
    }

    let companyId: string;
    let companyName: string;

    if (companyChoice === 'create') {
      const inviteCode = Math.random().toString(36).substring(2, 8).toUpperCase();
      
      const { data: company, error: companyError } = await supabaseAdmin
        .from('companies')
        .insert({
          name: companyNameOrCode,
          invite_code: inviteCode,
          created_by: userId
        })
        .select()
        .single();

      if (companyError || !company) {
        console.error('Company creation error:', companyError);
        return { success: false, error: 'Failed to create company. ' + companyError.message };
      }

      companyId = company.id;
      companyName = company.name;
    } else {
      const { data: company, error: companyError } = await supabaseAdmin
        .from('companies')
        .select('id, name')
        .eq('invite_code', companyNameOrCode)
        .single();

      if (companyError || !company) {
        return { success: false, error: 'Invalid invite code.' };
      }

      companyId = company.id;
      companyName = company.name;
    }
    
    const role = companyChoice === 'create' ? 'admin' : 'member';

    const { data: profile, error: profileError } = await supabaseAdmin
      .from('users')
      .insert({
        firebase_uid: userId,
        email: userEmail,
        company_id: companyId,
        role: role
      })
      .select()
      .single();

    if (profileError) {
      console.error('Profile creation error:', profileError);
      return { success: false, error: 'Failed to create user profile. ' + profileError.message };
    }

    // Set custom claims AFTER database operations are successful
    await adminAuth.setCustomUserClaims(userId, {
      companyId: companyId,
      role: profile.role
    });

    return {
      success: true,
      profile: {
        id: profile.firebase_uid,
        email: profile.email,
        role: profile.role,
        companyId: profile.company_id,
        company: {
          id: companyId,
          name: companyName
        }
      }
    };
  } catch (error: any) {
    console.error('Setup error:', error);
    return { success: false, error: 'An unexpected error occurred: ' + error.message };
  }
}

export async function ensureDemoUserExists(idToken: string) {
  if (!adminAuth || !supabaseAdmin) {
    return { success: false, error: 'Server not configured.' };
  }

  try {
    const decodedToken = await adminAuth.verifyIdToken(idToken);
    const userId = decodedToken.uid;
    const userEmail = decodedToken.email;

    if (!userEmail) {
      return { success: false, error: 'User email not found in token.' };
    }
    
    const { data: existingProfile } = await supabaseAdmin
      .from('users')
      .select('firebase_uid')
      .eq('firebase_uid', userId)
      .single();
    
    if (existingProfile) {
      return { success: true, message: 'Demo user already provisioned.' };
    }

    const demoCompanyId = '550e8400-e29b-41d4-a716-446655440001';
    
    const { data: company } = await supabaseAdmin
      .from('companies')
      .select('id')
      .eq('id', demoCompanyId)
      .single();

    if (!company) {
      await supabaseAdmin.from('companies').insert({
        id: demoCompanyId,
        name: 'Demo Company',
        invite_code: 'DEMO123',
        created_by: userId,
      });
    }
    
    await supabaseAdmin.from('users').insert({
      firebase_uid: userId,
      email: userEmail,
      company_id: demoCompanyId,
      role: 'admin',
    });

    // Set claims for the new demo user
    await adminAuth.setCustomUserClaims(userId, {
      companyId: demoCompanyId,
      role: 'admin',
    });

    return { success: true, message: 'Demo user created successfully.' };

  } catch (error: any) {
    console.error("Error provisioning demo user:", error.message);
    return { success: false, error: "Failed to provision demo environment." };
  }
}
