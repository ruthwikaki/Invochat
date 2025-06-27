
'use server';

import { GoogleGenerativeAI, HarmCategory, HarmBlockThreshold } from '@google/generative-ai';
import { supabaseAdmin } from '@/lib/supabase/admin';
import type { UniversalChatInput, UniversalChatOutput } from '@/types/ai-schemas';

// Ensure the GOOGLE_API_KEY is set, otherwise throw a startup error.
if (!process.env.GOOGLE_API_KEY) {
  throw new Error('FATAL: GOOGLE_API_KEY environment variable is not set.');
}
const genAI = new GoogleGenerativeAI(process.env.GOOGLE_API_KEY);

const model = genAI.getGenerativeModel({
  model: "gemini-1.5-pro", // Using a reliable model that supports this direct approach well
  safetySettings: [ // Set safety settings to be less restrictive for SQL generation
      {
        category: HarmCategory.HARM_CATEGORY_HARASSMENT,
        threshold: HarmBlockThreshold.BLOCK_NONE,
      },
      {
        category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
        threshold: HarmBlockThreshold.BLOCK_NONE,
      },
      {
        category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
        threshold: HarmBlockThreshold.BLOCK_NONE,
      },
      {
        category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
        threshold: HarmBlockThreshold.BLOCK_NONE,
      },
  ],
});


/**
 * This is the new, direct implementation that bypasses Genkit tools for reliability.
 * It uses a two-step process:
 * 1. Generate a SQL query from the user's prompt.
 * 2. Execute the query and use the results to generate a natural language response.
 */
export async function universalChatFlow(input: UniversalChatInput): Promise<UniversalChatOutput> {
  const { companyId, conversationHistory } = input;
  console.log('[UniversalChat:Direct] Starting flow for company', companyId);

  const userQuery = conversationHistory[conversationHistory.length - 1]?.content || '';
  if (!userQuery) {
    return { response: "Please provide a question.", data: [], visualization: { type: 'none' } };
  }
  
  // STEP 1: Generate SQL from user query
  const sqlGenerationPrompt = `
    Generate a single, read-only PostgreSQL SQL SELECT query to answer this question: "${userQuery}"

    DATABASE SCHEMA:
    - **inventory**: id, sku, name, description, category, quantity, cost, price, reorder_point, reorder_qty, supplier_name, warehouse_name, last_sold_date, company_id
    - **vendors**: id, vendor_name, contact_info, address, terms, account_number, company_id
    - **sales**: id, sale_date, customer_name, total_amount, items, company_id
    - **purchase_orders**: id, po_number, vendor, item, quantity, cost, order_date, company_id

    CRITICAL RULES:
    1. Your response MUST be ONLY the SQL query. Do not include any other text, explanations, or markdown formatting like \`\`\`sql.
    2. Every query MUST contain a WHERE clause to filter by the user's company. Use this exact clause: company_id = '${companyId}'
    3. You must use PostgreSQL syntax. For example, for date calculations, use constructs like (CURRENT_DATE - INTERVAL '90 days') instead of functions like DATE('now', '-90 days').
    4. If a user asks for a chart (e.g., "pie chart of..."), generate a query that produces aggregated data suitable for that chart (e.g., using GROUP BY and COUNT or SUM).
  `;

  let sqlQuery = '';
  try {
    const result = await model.generateContent(sqlGenerationPrompt);
    sqlQuery = result.response.text().trim().replace(/;/g, ''); // Clean trailing semicolon
    console.log('[UniversalChat:Direct] Generated SQL:', sqlQuery);
    
    if (!sqlQuery.toLowerCase().startsWith('select')) {
      throw new Error("AI did not generate a valid SELECT query.");
    }
  } catch (error: any) {
    console.error('[UniversalChat:Direct] Error generating SQL:', error);
    return {
      response: "I had trouble creating a database query for your request. Please try rephrasing it.",
      data: [],
      visualization: { type: 'none' }
    };
  }
  
  // STEP 2: Execute query and generate final response
  try {
    const { data: queryData, error: queryError } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: sqlQuery
    });

    if (queryError) {
      console.error('[UniversalChat:Direct] Database query failed:', queryError);
      return {
        response: `I encountered an issue with the database query: ${queryError.message}. Please try rephrasing your question.`,
        data: [], // Always return an array on error
        visualization: { type: 'none' }
      };
    }
    
    console.log('[UniversalChat:Direct] Query Result Data:', queryData);

    const finalResponsePrompt = `
      You are ARVO, an expert AI inventory management analyst.
      The user asked: "${userQuery}"
      You have already executed a database query and retrieved the following data as a JSON object:
      ${JSON.stringify(queryData, null, 2)}

      Your task is to provide a concise, natural language response based *only* on this data.
      - If the data is empty or null, state that you couldn't find any information for the request.
      - Do not mention SQL, databases, or JSON.
      - If the data looks like it's for a chart (e.g., categories and counts), briefly summarize it.
      - If the data is a list of items, state what the list contains.
    `;

    const result = await model.generateContent(finalResponsePrompt);
    const finalResponse = result.response.text();

    // Basic visualization suggestion
    let vizType: 'table' | 'bar' | 'pie' | 'line' | 'none' = 'none';
    if (queryData && queryData.length > 0) {
      vizType = 'table'; // Default to table if there's data
      const lowerQuery = userQuery.toLowerCase();
      if (lowerQuery.includes('pie chart')) vizType = 'pie';
      else if (lowerQuery.includes('bar chart') || lowerQuery.includes('barchart')) vizType = 'bar';
      else if (lowerQuery.includes('line chart')) vizType = 'line';
    }

    return {
      response: finalResponse,
      data: queryData || [],
      visualization: {
        type: vizType,
        title: userQuery
      }
    };

  } catch (error: any) {
    console.error('[UniversalChat:Direct] Error during final response generation:', error);
    return {
      response: `I successfully queried the database, but ran into an error while analyzing the results. The error was: ${error.message}`,
      data: [],
      visualization: { type: 'none' }
    };
  }
}
