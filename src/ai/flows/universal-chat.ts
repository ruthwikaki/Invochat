
'use server';
/**
 * @fileoverview Implements the advanced, multi-agent AI chat system for InvoChat.
 * This system uses a Chain-of-Thought approach with distinct steps for planning,
 * generation, validation, and response formulation to provide more accurate and
 * context-aware answers.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { supabaseAdmin } from '@/lib/supabase/admin';
import type { UniversalChatInput, UniversalChatOutput } from '@/types/ai-schemas';
import { UniversalChatInputSchema, UniversalChatOutputSchema } from '@/types/ai-schemas';
import { getDatabaseSchemaAndData as getDbSchema } from '@/services/database';

const model = 'gemini-1.5-pro'; // Use a powerful model for better reasoning

/**
 * Agent 1: SQL Generation
 * Takes the user query and generates a safe, advanced PostgreSQL query.
 */
const sqlGenerationPrompt = ai.definePrompt({
  name: 'sqlGenerationPrompt',
  input: { schema: z.object({ companyId: z.string(), userQuery: z.string(), dbSchema: z.string() }) },
  output: { schema: z.object({ sqlQuery: z.string().describe('The generated SQL query.'), reasoning: z.string().describe('A brief explanation of the query logic.') }) },
  prompt: `
    You are an expert SQL generation agent. Your task is to convert a user's question into a secure, read-only PostgreSQL query.
    
    DATABASE SCHEMA OVERVIEW:
    Here are the tables and columns you can query. Use this as your primary source of truth for the database structure.
    {{{dbSchema}}}
    
    SEMANTIC LAYER (Business Definitions):
    - "Dead stock": inventory items where 'last_sold_date' is more than 90 days ago.
    - "Low stock": inventory items where 'quantity' <= 'reorder_point'.
    - "Revenue" or "Sales Value": calculated from 'sales.total_amount'.
    - "Inventory Value": calculated by SUM(inventory.quantity * inventory.cost).

    USER'S QUESTION: "{{userQuery}}"

    CRITICAL GENERATION RULES:
    1.  **Security First**: The query MUST be a read-only SELECT statement. It MUST include a WHERE clause to filter by the user's company: \`company_id = '{{companyId}}'\`.
    2.  **Advanced SQL**: For complex requests (e.g., trends, comparisons), use Common Table Expressions (CTEs) or window functions.
    3.  **Syntax**: Use PostgreSQL syntax, like \`(CURRENT_DATE - INTERVAL '90 days')\` for date math.
    4.  **Output**: Respond with a JSON object containing 'sqlQuery' and 'reasoning'. The 'sqlQuery' must be ONLY the SQL string, without any markdown or trailing semicolons.
  `,
  config: { model },
});

/**
 * Agent 2: Query Validation
 * Reviews the generated SQL for security, correctness, and business sense.
 */
const queryValidationPrompt = ai.definePrompt({
  name: 'queryValidationPrompt',
  input: { schema: z.object({ userQuery: z.string(), sqlQuery: z.string() }) },
  output: { schema: z.object({ isValid: z.boolean(), correction: z.string().optional().describe('Reason if invalid.') }) },
  prompt: `
    You are a SQL validation agent. Review the generated SQL query.

    USER'S QUESTION: "{{userQuery}}"
    GENERATED SQL: \`\`\`sql\n{{sqlQuery}}\n\`\`\`

    VALIDATION CHECKLIST:
    1.  **Security**: Is it a read-only SELECT query? Does it contain a 'company_id' filter?
    2.  **Correctness**: Is the syntax valid PostgreSQL? Does it logically answer the user's question?
    3.  **Business Sense**: Does it use the correct columns/tables based on the question and business context?

    OUTPUT:
    - If valid, return \`{"isValid": true}\`.
    - If invalid, return \`{"isValid": false, "correction": "Explain the error concisely."}\`.
  `,
  config: { model },
});

/**
 * Agent 3: Result Interpretation & Response Generation
 * Analyzes the query result and formulates the final user-facing message.
 */
const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  input: { schema: z.object({ userQuery: z.string(), queryDataJson: z.string() }) },
  output: { schema: FinalResponseObjectSchema },
  prompt: `
    You are ARVO, an expert AI inventory analyst.
    The user asked: "{{userQuery}}"
    You have executed a database query and received this JSON data:
    {{{queryDataJson}}}

    YOUR TASK:
    1.  **Analyze Data**: Review the JSON. If it's empty or null, state that you found no information.
    2.  **Formulate Response**: Provide a concise, natural language response based ONLY on the data. Do NOT mention SQL, databases, or JSON.
    3.  **Suggest Visualization**: Based on the data's structure, suggest a visualization type ('table', 'bar', 'pie', 'line', or 'none') and a title for it.
    4.  **Format Output**: Return a single JSON object with 'response' and 'visualization' fields. Do NOT include the raw data in your response.
  `,
  config: { model },
});


/**
 * The main orchestrator flow that simulates the multi-agent pipeline.
 */
const universalChatOrchestrator = ai.defineFlow(
  {
    name: 'universalChatOrchestrator',
    inputSchema: UniversalChatInputSchema,
    outputSchema: UniversalChatOutputSchema,
  },
  async (input) => {
    const { companyId, conversationHistory } = input;
    const userQuery = conversationHistory[conversationHistory.length - 1]?.content || '';
    
    if (!userQuery) {
        throw new Error("User query was empty.");
    }
    
    // Pipeline Step 0: Fetch dynamic DB schema to provide context to the AI
    const schemaData = await getDbSchema(companyId);
    const formattedSchema = schemaData.map(table => 
        `Table: ${table.tableName} | Columns: ${table.rows.length > 0 ? Object.keys(table.rows[0]).join(', ') : 'No columns detected or table is empty'}`
    ).join('\n');

    // Pipeline Step 1: Generate SQL
    const { output: generationOutput } = await sqlGenerationPrompt({ companyId, userQuery, dbSchema: formattedSchema });
    if (!generationOutput?.sqlQuery) {
        throw new Error("AI failed to generate an SQL query.");
    }
    const { sqlQuery } = generationOutput;

    // Pipeline Step 2: Validate SQL
    const { output: validationOutput } = await queryValidationPrompt({ userQuery, sqlQuery });
    if (!validationOutput?.isValid) {
        console.error("Generated SQL failed validation:", validationOutput.correction);
        throw new Error(`The generated query was invalid. Reason: ${validationOutput.correction}`);
    }

    // Pipeline Step 3: Execute Query
    const { data: queryData, error: queryError } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: sqlQuery.replace(/;/g, '')
    });

    if (queryError) {
      console.error('[UniversalChat:Flow] Database query failed:', queryError);
      throw new Error(`The database query failed: ${queryError.message}.`);
    }

    // Pipeline Step 4: Interpret Results and Generate Final Response
    const queryDataJson = JSON.stringify(queryData || []);
    const { output: finalOutput } = await finalResponsePrompt({ userQuery, queryDataJson });
    if (!finalOutput) {
      throw new Error('The AI model did not return a valid final response object.');
    }
    
    // Manually construct the full response object
    return {
        ...finalOutput,
        data: queryData || [],
    };
  }
);

// The exported function that server actions will call. It's now the robust, orchestrated flow.
export const universalChatFlow = universalChatOrchestrator;
