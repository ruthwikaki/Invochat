
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
    You are an expert PostgreSQL query generation agent for an inventory management system. Your primary function is to translate a user's natural language question into a secure, efficient, and advanced SQL query.

    DATABASE SCHEMA OVERVIEW:
    {{{dbSchema}}}

    SEMANTIC LAYER (Business Definitions):
    - "Dead stock": inventory items where 'last_sold_date' is more than 90 days ago.
    - "Low stock": inventory items where 'quantity' <= 'reorder_point'.
    - "Revenue" or "Sales": calculated from 'sales.total_amount'.
    - "Inventory Value": calculated by SUM(inventory.quantity * inventory.cost).

    USER'S QUESTION: "{{userQuery}}"

    **QUERY GENERATION PROCESS (You MUST follow these steps):**

    **Step 1: Analyze Query Complexity.**
    - Is the user asking for a simple list (e.g., "list all suppliers")? This is a **SIMPLE** query.
    - Is the user asking for trends, comparisons, rankings, growth, or multi-step calculations (e.g., "top 5 products by sales growth", "compare this month's sales to last month", "suppliers with the most dead stock")? This is a **COMPLEX ANALYTICAL** query.

    **Step 2: Apply Generation Rules based on Complexity.**

    **A) For ALL Queries:**
    1.  **Security is paramount**: The query MUST be a read-only \`SELECT\` statement.
    2.  **Mandatory Filtering**: Every table referenced (including in joins) MUST include a \`WHERE\` clause filtering by the user's company: \`company_id = '{{companyId}}'\`. This is a non-negotiable security requirement.
    3.  **Syntax**: Use PostgreSQL syntax, like \`(CURRENT_DATE - INTERVAL '90 days')\` for date math.

    **B) For COMPLEX ANALYTICAL Queries:**
    4.  **Advanced SQL is MANDATORY**: You MUST use advanced SQL features to ensure readability and correctness.
        - **Common Table Expressions (CTEs)** are REQUIRED to break down complex logic. Do not use nested subqueries where a CTE would be clearer.
        - **Window Functions** (e.g., \`RANK()\`, \`LEAD()\`, \`LAG()\`, \`SUM() OVER (...)\`) MUST be used for rankings, period-over-period comparisons, and cumulative totals.

    **Step 3: Generate the Query.**

    **Example of a COMPLEX ANALYTICAL Query:**
    For a question like "show me the top 3 products by sales this month", a correct query that follows the rules would be:
    \`\`\`sql
    WITH MonthlySales AS (
        SELECT
            product_id,
            SUM(total_amount) as total_sales
        FROM sales
        WHERE company_id = '{{companyId}}' AND sale_date >= date_trunc('month', CURRENT_DATE)
        GROUP BY product_id
    )
    SELECT
        i.name,
        ms.total_sales
    FROM MonthlySales ms
    JOIN inventory i ON ms.product_id = i.id AND i.company_id = '{{companyId}}'
    ORDER BY ms.total_sales DESC
    LIMIT 3
    \`\`\`

    **Step 4: Formulate the Final Output.**
    - Respond with a JSON object containing \`sqlQuery\` and \`reasoning\`.
    - The \`sqlQuery\` field MUST contain ONLY the SQL string. Do not include markdown or trailing semicolons.
    - The \`reasoning\` field must briefly explain the logic, especially for complex queries (e.g., "Used a CTE to calculate monthly sales first, then joined with inventory to get product names.").
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
    GENERATED SQL: \`\`\`sql
{{sqlQuery}}
\`\`\`

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
 * Agent 3: Error Recovery
 * Analyzes a failed query and its error message to suggest a correction.
 */
const errorRecoveryPrompt = ai.definePrompt({
    name: 'errorRecoveryPrompt',
    input: { schema: z.object({ userQuery: z.string(), failedQuery: z.string(), errorMessage: z.string(), dbSchema: z.string() }) },
    output: { schema: z.object({ correctedQuery: z.string().optional().describe('The corrected SQL query, if fixable.'), reasoning: z.string().describe('Explanation of the error and the fix.') }) },
    prompt: `
        You are an expert SQL debugging agent. Your task is to analyze a failed PostgreSQL query and its error message, then provide a corrected query.

        DATABASE SCHEMA FOR REFERENCE:
        {{{dbSchema}}}

        USER'S ORIGINAL QUESTION: "{{userQuery}}"

        FAILED SQL QUERY:
        \`\`\`sql
        {{failedQuery}}
        \`\`\`

        DATABASE ERROR MESSAGE:
        "{{errorMessage}}"

        ANALYSIS & CORRECTION RULES:
        1.  **Analyze the Error**: Carefully read the error message. Common errors include non-existent columns (e.g., 'column "X" does not exist'), syntax errors, or type mismatches.
        2.  **Refer to the Schema**: Use the provided database schema to verify table and column names.
        3.  **Propose a Fix**: Generate a \`correctedQuery\`. The goal is to fix the error while still answering the user's original question.
        4.  **Do Not Change Intent**: The corrected query must not alter the original intent of the user's question.
        5.  **Explain Your Reasoning**: Briefly explain what was wrong and how you fixed it in the \`reasoning\` field.
        6.  **If Unfixable**: If the error is ambiguous or you cannot confidently fix it, do not provide a \`correctedQuery\`. Explain why in the \`reasoning\` field instead.
        7.  **Security**: The corrected query must still be a read-only SELECT statement and must contain the company_id filter.
    `,
    config: { model },
});


/**
 * Agent 4: Result Interpretation & Response Generation
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
    let sqlQuery = generationOutput.sqlQuery;

    // Pipeline Step 2: Validate SQL
    const { output: validationOutput } = await queryValidationPrompt({ userQuery, sqlQuery });
    if (!validationOutput?.isValid) {
        console.error("Generated SQL failed validation:", validationOutput.correction);
        throw new Error(`The generated query was invalid. Reason: ${validationOutput.correction}`);
    }

    // Pipeline Step 3: Execute Query with Error Recovery
    let { data: queryData, error: queryError } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: sqlQuery.replace(/;/g, '')
    });
    
    // Pipeline Step 3b: Error Recovery (if needed)
    if (queryError) {
        console.warn(`[UniversalChat:Flow] Initial query failed: "${queryError.message}". Attempting recovery...`);
        
        const { output: recoveryOutput } = await errorRecoveryPrompt({
            userQuery,
            failedQuery: sqlQuery,
            errorMessage: queryError.message,
            dbSchema: formattedSchema,
        });

        if (recoveryOutput?.correctedQuery) {
            console.log(`[UniversalChat:Flow] AI provided a corrected query. Reasoning: ${recoveryOutput.reasoning}`);
            
            // Retry with the new query
            sqlQuery = recoveryOutput.correctedQuery; // Update the query to the corrected one
            const retryResult = await supabaseAdmin.rpc('execute_dynamic_query', {
                query_text: sqlQuery.replace(/;/g, '')
            });
            
            queryData = retryResult.data;
            queryError = retryResult.error;

            if (queryError) {
                console.error('[UniversalChat:Flow] Corrected query also failed:', queryError.message);
                // Throw a more user-friendly error if the retry fails
                throw new Error(`I tried to automatically fix a query error, but the correction also failed. The original error was: ${queryError.message}`);
            } else {
                console.log('[UniversalChat:Flow] Corrected query executed successfully.');
            }
        } else {
            // If AI can't fix it, throw the original error
            console.error('[UniversalChat:Flow] AI could not recover from the query error.');
            throw new Error(`The database query failed: ${queryError.message}.`);
        }
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
