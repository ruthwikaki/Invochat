
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
import { getDatabaseSchemaAndData as getDbSchema, getQueryPatternsForCompany, saveSuccessfulQuery, getCompanySettings } from '@/services/database';
import { APP_CONFIG } from '@/config/app-config';

// Updated few-shot examples to reflect the new, richer schema
const FEW_SHOT_EXAMPLES = `
  1. User asks: "Show me products that haven't sold in 90 days"
     SQL:
     SELECT p.name, p.sku, p.quantity
     FROM products p
     WHERE p.company_id = '{{companyId}}'
       AND NOT EXISTS (
         SELECT 1
         FROM sales_detail sd
         JOIN sales s ON sd.sale_id = s.id
         WHERE sd.product_id = p.id
           AND s.sale_date >= (CURRENT_DATE - INTERVAL '90 days')
       )
     ORDER BY p.name;

  2. User asks: "Which suppliers have the most products that are low on stock?"
     SQL:
     WITH LowStockCounts AS (
        SELECT
            p.supplier_name,
            COUNT(p.id) as low_stock_product_count
        FROM products p
        WHERE p.company_id = '{{companyId}}' AND p.quantity <= p.reorder_point
        GROUP BY p.supplier_name
     )
     SELECT
        v.vendor_name,
        lsc.low_stock_product_count
     FROM LowStockCounts lsc
     JOIN vendors v ON lsc.supplier_name = v.vendor_name AND v.company_id = '{{companyId}}'
     ORDER BY lsc.low_stock_product_count DESC;

  3. User asks: "Compare sales this month to last month for each product category"
     SQL:
     WITH MonthlySales AS (
        SELECT
            p.category,
            date_trunc('month', s.sale_date) as sales_month,
            SUM(sd.quantity * sd.price) as total_sales
        FROM sales_detail sd
        JOIN sales s ON sd.sale_id = s.id
        JOIN products p ON sd.product_id = p.id
        WHERE s.company_id = '{{companyId}}'
          AND s.sale_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
        GROUP BY 1, 2
     )
     SELECT
        category,
        total_sales,
        LAG(total_sales, 1) OVER (PARTITION BY category ORDER BY sales_month) as previous_month_sales
     FROM MonthlySales
     ORDER BY category, sales_month DESC;
`;


/**
 * Agent 1: SQL Generation
 * Takes the user query and generates a safe, advanced PostgreSQL query.
 */
const sqlGenerationPrompt = ai.definePrompt({
  name: 'sqlGenerationPrompt',
  input: { schema: z.object({ companyId: z.string(), userQuery: z.string(), dbSchema: z.string(), semanticLayer: z.string(), dynamicExamples: z.string() }) },
  output: { schema: z.object({ sqlQuery: z.string().describe('The generated SQL query.'), reasoning: z.string().describe('A brief explanation of the query logic.') }) },
  prompt: `
    You are an expert PostgreSQL query generation agent for an e-commerce analytics system. Your primary function is to translate a user's natural language question into a secure, efficient, and advanced SQL query.

    DATABASE SCHEMA OVERVIEW:
    {{{dbSchema}}}

    SEMANTIC LAYER (Business Definitions):
    {{{semanticLayer}}}

    USER'S QUESTION: "{{userQuery}}"

    **QUERY GENERATION PROCESS (You MUST follow these steps):**

    **A) For ALL Queries (NON-NEGOTIABLE):**
    1.  **Security is paramount**: The query MUST be a read-only \`SELECT\` statement.
    2.  **Mandatory Filtering**: Every table referenced (including in joins and subqueries) MUST include a \`WHERE\` clause filtering by the user's company: \`company_id = '{{companyId}}'\`. This is a non-negotiable security requirement.
    3.  **Column Verification**: Before using a column in a JOIN, WHERE, or SELECT clause, you MUST verify that the column exists in the respective table by checking the DATABASE SCHEMA OVERVIEW. Do not hallucinate column names.
    4.  **Syntax**: Use PostgreSQL syntax, like \`(CURRENT_DATE - INTERVAL '90 days')\` for date math.
    5.  **NO Cross Joins**: NEVER use implicit cross joins (e.g., \`FROM table1, table2\`). Always specify a valid JOIN condition using \`ON\` (e.g., \`FROM products JOIN vendors ON products.supplier_id = vendors.id\`).

    **B) For COMPLEX ANALYTICAL Queries:**
    6.  **Advanced SQL is MANDATORY**: You MUST use advanced SQL features to ensure readability and correctness.
        - **Common Table Expressions (CTEs)** are REQUIRED to break down complex logic. Do not use nested subqueries where a CTE would be clearer.
        - **Window Functions** (e.g., \`RANK()\`, \`LEAD()\`, \`LAG()\`, \`SUM() OVER (...)\`) MUST be used for rankings, period-over-period comparisons, and cumulative totals.
    7.  **Calculations**: If the user asks for a calculated metric (like 'turnover rate' or 'growth'), you MUST include the full calculation in the SQL. Do not just select the raw data and assume the calculation will be done elsewhere.

    **Step 3: Consult Examples for Structure.**
    Review these examples to understand the expected query style.
    ---
    FEW-SHOT EXAMPLES (General):
    ${FEW_SHOT_EXAMPLES}
    ---
    ---
    COMPANY-SPECIFIC EXAMPLES (Queries that have worked for this company before):
    {{{dynamicExamples}}}
    ---

    **Step 4: Generate the Query.**
    Based on the analysis, rules, and examples, generate the SQL query that best answers the user's question.

    **Step 5: Formulate the Final Output.**
    - Respond with a JSON object containing \`sqlQuery\` and \`reasoning\`.
    - The \`sqlQuery\` field MUST contain ONLY the SQL string. Do not include markdown or trailing semicolons.
    - The \`reasoning\` field must briefly explain the logic, especially for complex queries (e.g., "Used a CTE to calculate monthly sales first, then joined with products to get product names.").
  `,
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
    You are a SQL validation agent. Review the generated SQL query with extreme scrutiny.

    USER'S QUESTION: "{{userQuery}}"
    GENERATED SQL: \`\`\`sql
{{sqlQuery}}
\`\`\`

    VALIDATION CHECKLIST:
    1.  **Security**: Is it a read-only SELECT query? Does EVERY table reference (including joins) contain a 'company_id' filter?
    2.  **Correctness**: Is the syntax valid PostgreSQL? Does it logically answer the user's question?
    3.  **Business Sense**: Does it use the correct columns/tables based on the question and business context? Does it avoid nonsensical operations like cross joins? If the user asked for a metric like 'turnover', is the calculation present and correct?

    OUTPUT:
    - If valid, return \`{"isValid": true}\`.
    - If invalid, return \`{"isValid": false, "correction": "Explain the error concisely and technically."}\`. For example: "The query uses a cross join between vendors and products, which is invalid. It should use an explicit JOIN ON a shared key." or "The query is missing the calculation for inventory turnover rate."
  `,
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
    2.  **Assess Confidence**: Based on the user's query and the data, provide a confidence score from 0.0 to 1.0. A 1.0 means you are certain the query fully answered the user's request. A lower score means you had to make assumptions.
    3.  **List Assumptions**: If your confidence is below 1.0, list the assumptions you made (e.g., "Interpreted 'top products' as 'top by sales value'"). If confidence is 1.0, return an empty array.
    4.  **Formulate Response**: Provide a concise, natural language response based ONLY on the data. Do NOT mention SQL, databases, or JSON.
    5.  **Suggest Visualization**: Based on the data's structure, suggest a visualization type and a title for it. Available types are:
        - 'table': For detailed, row-based data.
        - 'bar': For comparing distinct items.
        - 'pie': For showing proportions of a whole.
        - 'line': For showing trends over time.
        - 'treemap': For hierarchical data or showing parts of a whole with nested rectangles. Good for inventory value by category and then by product.
        - 'none': If no visualization is appropriate.
    6.  **Format Output**: Return a single JSON object with 'response', 'visualization', 'confidence', and 'assumptions' fields. Do NOT include the raw data in your response.
  `,
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
    
    // Pipeline Step 0: Fetch dynamic data in parallel for speed
    const [schemaData, settings, dynamicPatterns] = await Promise.all([
        getDbSchema(companyId),
        getCompanySettings(companyId),
        getQueryPatternsForCompany(companyId)
    ]);

    const formattedSchema = schemaData.map(table => 
        `Table: ${table.tableName} | Columns: ${table.rows.length > 0 ? Object.keys(table.rows[0]).join(', ') : 'No columns detected or table is empty'}`
    ).join('\n');
    
    const { businessLogic } = APP_CONFIG; // For seasonalCategories, which aren't in settings yet
    
    // Updated Semantic Layer for the new schema
    const semanticLayer = `
      - "Dead stock": products that have not appeared in a 'sales_detail' record where the 'sales.sale_date' is more recent than ${settings.dead_stock_days} days ago.
      - "Low stock": products where 'quantity' <= 'reorder_point'.
      - "Revenue" or "Sales": calculated from 'sales.total_amount' or by summing 'sales_detail.price * sales_detail.quantity'.
      - "Inventory Value": calculated by SUM(products.quantity * products.cost).
      - "Fast-moving items": products sold in the last ${settings.fast_moving_days} days.
      - "Overstock": items with quantity > (reorder_point * ${settings.overstock_multiplier}).
      - "High-value items": products where cost > ${settings.high_value_threshold}.
      - "Seasonal items": products with category in (${businessLogic.seasonalCategories.map(c => `'${c}'`).join(', ')}).
    `;

    const formattedDynamicPatterns = dynamicPatterns.map((p, i) => 
        // Continue numbering from the static examples
        `${FEW_SHOT_EXAMPLES.trim().split('\n\n').length + i + 1}. User asks: "${p.user_question}"\n   SQL:\n   ${p.successful_sql_query}`
    ).join('\n\n');

    const aiModel = APP_CONFIG.ai.model;

    // Pipeline Step 1: Generate SQL
    const { output: generationOutput } = await sqlGenerationPrompt(
      { companyId, userQuery, dbSchema: formattedSchema, semanticLayer, dynamicExamples: formattedDynamicPatterns },
      { model: aiModel }
    );
    if (!generationOutput?.sqlQuery) {
        throw new Error("AI failed to generate an SQL query.");
    }
    let sqlQuery = generationOutput.sqlQuery;

    // Pipeline Step 2: Validate SQL
    const { output: validationOutput } = await queryValidationPrompt(
        { userQuery, sqlQuery },
        { model: aiModel }
    );
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
        
        const { output: recoveryOutput } = await errorRecoveryPrompt(
            { userQuery, failedQuery: sqlQuery, errorMessage: queryError.message, dbSchema: formattedSchema },
            { model: aiModel }
        );

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
                throw new Error(`I tried to automatically fix a query error, but the correction also failed. The original error was: ${queryError.message}`);
            } else {
                console.log('[UniversalChat:Flow] Corrected query executed successfully.');
            }
        } else {
            console.error('[UniversalChat:Flow] AI could not recover from the query error.');
            throw new Error(`The database query failed: ${queryError.message}.`);
        }
    }

    // NEW STEP: If query execution was successful, save the pattern for future learning.
    if (!queryError) {
        await saveSuccessfulQuery(companyId, userQuery, sqlQuery);
    }

    // Pipeline Step 4: Interpret Results and Generate Final Response
    const queryDataJson = JSON.stringify(queryData || []);
    const { output: finalOutput } = await finalResponsePrompt(
        { userQuery, queryDataJson },
        { model: aiModel }
    );
    if (!finalOutput) {
      throw new Error('The AI model did not return a valid final response object.');
    }
    
    console.log(`[UniversalChat:Flow] AI Confidence for query "${userQuery}": ${finalOutput.confidence}`);
    if (finalOutput.assumptions && finalOutput.assumptions.length > 0) {
        console.log(`[UniversalChat:Flow] AI Assumptions: ${finalOutput.assumptions.join(', ')}`);
    }

    return {
        ...finalOutput,
        data: queryData || [],
    };
  }
);

export const universalChatFlow = universalChatOrchestrator;
