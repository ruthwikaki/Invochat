
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
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';

const ENHANCED_SEMANTIC_LAYER = `
  BUSINESS METRICS:
  - "Inventory turnover rate": COGS / Average Inventory Value (industry standard: 5-10x/year)
  - "Sell-through rate": (Units Sold / Units Received) * 100
  - "GMROI" (Gross Margin Return on Investment): Gross Margin $ / Average Inventory Cost
  - "Stock to sales ratio": Average Inventory / Daily Sales Rate
  - "Carrying cost": Storage + Insurance + Taxes + Depreciation + Opportunity Cost
  - "Economic order quantity (EOQ)": sqrt((2 * Annual Demand * Order Cost) / Holding Cost)
  - "Days sales of inventory (DSI)": (Average Inventory / COGS) * 365
  - "Customer lifetime value (CLV)": Average Order Value * Purchase Frequency * Customer Lifespan
  - "ABC Analysis": A items (80% revenue), B items (15% revenue), C items (5% revenue)
  - "XYZ Analysis": X (steady demand), Y (variable demand), Z (irregular demand)
  
  TIME INTELLIGENCE:
  - "YoY" (Year over Year): Compare to same period last year
  - "MoM" (Month over Month): Compare to previous month
  - "QoQ" (Quarter over Quarter): Compare to previous quarter
  - "YTD" (Year to Date): From Jan 1 to current date
  - "MTD" (Month to Date): From month start to current date
  - "Rolling 12 months": Last 365 days
  - "Same period last year": date - INTERVAL '1 year'
  - "Seasonality": Identify patterns that repeat annually
  
  ADVANCED ANALYTICS:
  - "Trend analysis": Linear regression over time periods
  - "Outliers": Values beyond 2 standard deviations
  - "Correlation": Relationship between two metrics
  - "Price elasticity": Change in demand relative to price changes
  - "Basket analysis": Products frequently bought together
  - "Cohort analysis": Group customers by shared characteristics
  - "RFM analysis": Recency, Frequency, Monetary value segmentation
  
  SUPPLY CHAIN METRICS:
  - "Lead time": Days between order and receipt
  - "Safety stock": Buffer inventory for demand variability
  - "Reorder point": (Average Daily Usage * Lead Time) + Safety Stock
  - "Service level": Probability of not stocking out
  - "Fill rate": Orders fulfilled from stock / Total orders
  - "Perfect order rate": Orders delivered complete, on time, damage-free
  
  FINANCIAL METRICS:
  - "Gross margin": (Revenue - COGS) / Revenue
  - "Operating margin": Operating Income / Revenue
  - "Cash conversion cycle": DSI + Days Sales Outstanding - Days Payable Outstanding
  - "Working capital": Current Assets - Current Liabilities
  - "Return on assets (ROA)": Net Income / Total Assets
`;

const BUSINESS_QUERY_EXAMPLES = `
  4. Forecasting Query:
     User: "Forecast next month's demand for my top 10 products"
     SQL: WITH historical_sales AS (
       SELECT sku, 
              DATE_TRUNC('month', sale_date) as month,
              SUM(quantity) as monthly_quantity
       FROM sales_detail
       WHERE company_id = '{{companyId}}'
         AND sale_date >= CURRENT_DATE - INTERVAL '12 months'
       GROUP BY sku, month
     ),
     trend_analysis AS (
       SELECT sku,
              REGR_SLOPE(monthly_quantity, EXTRACT(epoch FROM month)) as trend,
              REGR_INTERCEPT(monthly_quantity, EXTRACT(epoch FROM month)) as base,
              AVG(monthly_quantity) as avg_monthly,
              STDDEV(monthly_quantity) as stddev_monthly
       FROM historical_sales
       GROUP BY sku
     )
     SELECT t.sku, 
            iv.product_name,
            ROUND(t.base + t.trend * EXTRACT(epoch FROM DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month')))) as forecasted_quantity,
            t.avg_monthly as historical_average,
            ROUND(t.stddev_monthly) as demand_variability
     FROM trend_analysis t
     JOIN inventory_valuation iv ON t.sku = iv.sku AND iv.company_id = '{{companyId}}'
     ORDER BY t.avg_monthly DESC
     LIMIT 10;

  5. ABC Analysis Query:
     User: "Perform ABC analysis on my inventory"
     SQL: WITH product_revenue AS (
       SELECT iv.sku,
              iv.product_name,
              SUM(sd.quantity * sd.unit_price) as total_revenue,
              SUM(sd.quantity) as total_units
       FROM inventory_valuation iv
       JOIN sales_detail sd ON iv.sku = sd.sku
       WHERE iv.company_id = '{{companyId}}' AND sd.company_id = '{{companyId}}'
         AND sd.sale_date >= CURRENT_DATE - INTERVAL '12 months'
       GROUP BY iv.sku, iv.product_name
     ),
     revenue_ranking AS (
       SELECT *,
              SUM(total_revenue) OVER (ORDER BY total_revenue DESC) as cumulative_revenue,
              SUM(total_revenue) OVER () as grand_total_revenue,
              ROW_NUMBER() OVER (ORDER BY total_revenue DESC) as rank
       FROM product_revenue
     )
     SELECT sku, 
            product_name,
            total_revenue,
            total_units,
            ROUND((cumulative_revenue / grand_total_revenue) * 100, 2) as cumulative_percentage,
            CASE 
              WHEN cumulative_revenue / grand_total_revenue <= 0.8 THEN 'A'
              WHEN cumulative_revenue / grand_total_revenue <= 0.95 THEN 'B'
              ELSE 'C'
            END as abc_category
     FROM revenue_ranking
     ORDER BY rank;
`;


// Updated few-shot examples to reflect the new, richer schema
const FEW_SHOT_EXAMPLES = `
  1. User asks: "Who were my top 5 customers last month?"
     SQL:
     SELECT
        c.name,
        SUM(s.total_amount) as total_spent
     FROM sales s
     JOIN customers c ON s.customer_id = c.id
     WHERE s.company_id = '{{companyId}}'
       AND c.company_id = '{{companyId}}'
       AND s.sale_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
       AND s.sale_date < date_trunc('month', CURRENT_DATE)
     GROUP BY c.name
     ORDER BY total_spent DESC
     LIMIT 5;

  2. User asks: "What was my return rate last month?"
     SQL:
     WITH MonthlySales AS (
         SELECT COUNT(id) as total_sales
         FROM sales
         WHERE company_id = '{{companyId}}'
           AND sale_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
           AND sale_date < date_trunc('month', CURRENT_DATE)
     ),
     MonthlyReturns AS (
         SELECT COUNT(id) as total_returns
         FROM returns
         WHERE company_id = '{{companyId}}'
           AND return_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
           AND return_date < date_trunc('month', CURRENT_DATE)
     )
     SELECT
        ms.total_sales,
        mr.total_returns,
        (mr.total_returns::decimal / ms.total_sales) * 100 as return_rate_percentage
     FROM MonthlySales ms, MonthlyReturns mr;

  3. User asks: "What was my total inventory value in the 'Main Warehouse'?"
     SQL:
     SELECT SUM(iv.quantity * iv.cost) as total_inventory_value
     FROM inventory_valuation iv
     JOIN warehouse_locations wl ON iv.warehouse_id = wl.id
     WHERE iv.company_id = '{{companyId}}'
       AND wl.company_id = '{{companyId}}'
       AND wl.warehouse_name = 'Main Warehouse';

  ${BUSINESS_QUERY_EXAMPLES}
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

    **A) For ALL Queries (NON-NEGOTIABLE SECURITY RULES):**
    1.  **Security is PARAMOUNT**: The query MUST be a read-only \`SELECT\` statement. You are FORBIDDEN from generating \`INSERT\`, \`UPDATE\`, \`DELETE\`, \`DROP\`, \`GRANT\`, or any other data-modifying or access-control statements.
    2.  **Mandatory Filtering**: Every table referenced (including in joins and subqueries) MUST include a \`WHERE\` clause filtering by the user's company: \`company_id = '{{companyId}}'\`. This is a non-negotiable security requirement. There are no exceptions.
    3.  **Column Verification**: Before using a column in a JOIN, WHERE, or SELECT clause, you MUST verify that the column exists in the respective table by checking the DATABASE SCHEMA OVERVIEW. Do not hallucinate column names.
    4.  **NO SQL Comments**: The final query MUST NOT contain any SQL comments (e.g., --, /* */).
    5.  **Syntax**: Use PostgreSQL syntax, like \`(CURRENT_DATE - INTERVAL '90 days')\` for date math.
    6.  **NO Cross Joins**: NEVER use implicit cross joins (e.g., \`FROM table1, table2\`). Always specify a valid JOIN condition using \`ON\` (e.g., \`FROM sales JOIN customers ON sales.customer_id = customers.id\`).

    **B) For COMPLEX ANALYTICAL Queries:**
    7.  **Advanced SQL is MANDATORY**: You MUST use advanced SQL features to ensure readability and correctness.
        - **Common Table Expressions (CTEs)** are REQUIRED to break down complex logic. Do not use nested subqueries where a CTE would be clearer.
        - **Window Functions** (e.g., \`RANK()\`, \`LEAD()\`, \`LAG()\`, \`SUM() OVER (...)\`) MUST be used for rankings, period-over-period comparisons, and cumulative totals.
    8.  **Calculations**: If the user asks for a calculated metric (like 'turnover rate' or 'growth' or 'return rate'), you MUST include the full calculation in the SQL. Do not just select the raw data and assume the calculation will be done elsewhere.

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
    - The \`reasoning\` field must briefly explain the logic, especially for complex queries (e.g., "Used a CTE to calculate monthly sales first, then joined with customers to get customer names.").
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
    You are a SQL validation agent. Review the generated SQL query with EXTREME SCRUTINY. Your primary job is to prevent any unsafe or incorrect queries from executing.

    USER'S QUESTION: "{{userQuery}}"
    GENERATED SQL: \`\`\`sql
{{sqlQuery}}
\`\`\`

    **SECURITY VALIDATION CHECKLIST (FAIL THE QUERY IF ANY OF THESE ARE TRUE):**
    1.  **Check for Forbidden Keywords**: Does the query contain ANY of the following keywords (case-insensitive)?
        - \`INSERT\`, \`UPDATE\`, \`DELETE\`, \`DROP\`, \`TRUNCATE\`, \`ALTER\`, \`GRANT\`, \`REVOKE\`, \`CREATE\`, \`EXECUTE\`
        If yes, FAIL validation immediately.
    2.  **Check for SQL Comments**: Does the query contain SQL comments (\`--\` or \`/*\`)?
        If yes, FAIL validation. Comments can be used to hide malicious code.
    3.  **Mandatory Company ID Filter**: Does EVERY table reference (including joins, subqueries, and CTEs) have a \`WHERE\` clause that filters by \`company_id\`?
        If even one is missing, FAIL validation.
    4.  **Read-Only Check**: Is the query a read-only \`SELECT\` statement?
        If it's anything else, FAIL validation.

    **LOGIC & CORRECTNESS CHECKLIST:**
    5.  **Syntax Validity**: Is the syntax valid for PostgreSQL?
    6.  **Logical Answer**: Does the query logically answer the user's question?
    7.  **Business Sense**: Does it use the correct columns/tables based on the question and business context? If the user asked for a metric like 'turnover', is the calculation present and correct?

    **OUTPUT FORMAT:**
    - If ALL security and logic checks pass, return \`{"isValid": true}\`.
    - If ANY check fails, return \`{"isValid": false, "correction": "Explain the specific reason for failure concisely and technically."}\`.
      - Example (Security Fail): "The query is missing a 'company_id' filter on the 'customers' table."
      - Example (Security Fail): "The query contains a forbidden 'UPDATE' keyword."
      - Example (Logic Fail): "The query uses a cross join between vendors and products, which is invalid."
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
        7.  **Security**: The corrected query must still be a read-only SELECT statement and must contain the company_id filter on all tables. It must not contain SQL comments.
    `,
});


/**
 * Tool: External Data Integration
 * A placeholder tool that simulates fetching external economic data.
 */
const getEconomicIndicators = ai.defineTool(
    {
        name: 'getEconomicIndicators',
        description: 'Returns current key economic indicators and industry benchmarks for context.',
        inputSchema: z.object({}), // No input needed for this simple version
        outputSchema: z.object({
            inflationRate: z.number().describe('The current annualized inflation rate as a percentage.'),
            industryAverageTurnover: z.number().describe('The average inventory turnover rate for the retail industry.'),
        }),
    },
    async () => {
        // In a real application, this would call an external API.
        // For now, we return hardcoded placeholder values.
        logger.info('[Tool Call] getEconomicIndicators invoked.');
        return {
            inflationRate: 3.5, // Placeholder value
            industryAverageTurnover: 6.0, // Placeholder value
        };
    }
);


/**
 * Agent 4: Result Interpretation & Response Generation
 * Analyzes the query result and formulates the final user-facing message.
 */
const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  tools: [getEconomicIndicators],
  input: { schema: z.object({ userQuery: z.string(), queryDataJson: z.string() }) },
  output: { schema: FinalResponseObjectSchema },
  prompt: `
    You are ARVO, an expert AI inventory analyst.
    The user asked: "{{userQuery}}"
    You have executed a database query and received this JSON data:
    {{{queryDataJson}}}

    YOUR TASK:
    1.  **Analyze Data & Context**:
        - Review the JSON data. If it's empty or null, state that you found no information.
        - **If the user's query implies a need for broader context** (e.g., asking about performance, growth, or comparisons), use the \`getEconomicIndicators\` tool to fetch data like inflation or industry benchmarks.
    2.  **Formulate Response**:
        - Provide a concise, natural language response based on the database data and any external context you fetched.
        - Do NOT mention SQL, databases, or JSON.
        - If you used the tool, weave the external data into your analysis seamlessly (e.g., "Your revenue grew by 5%, which is outpacing the current inflation rate of 3.5%.").
    3.  **Assess Confidence**: Based on the user's query and the data, provide a confidence score from 0.0 to 1.0. A 1.0 means you are certain the query fully answered the user's request. A lower score means you had to make assumptions.
    4.  **List Assumptions**: If your confidence is below 1.0, list the assumptions you made (e.g., "Interpreted 'top products' as 'top by sales value'"). If confidence is 1.0, return an empty array.
    5.  **Suggest Visualization**: Based on the data's structure, suggest a visualization type and a title for it. Available types are:
        - 'table': For detailed, row-based data.
        - 'bar': For comparing distinct items.
        - 'pie': For showing proportions of a whole.
        - 'line': For showing trends over time.
        - 'treemap': For hierarchical data or showing parts of a whole with nested rectangles. Good for inventory value by category and then by product.
        - 'scatter': For showing the relationship or correlation between two numerical variables (e.g., price vs. units sold). Data should have 'x' and 'y' keys.
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
    
    const semanticLayer = ENHANCED_SEMANTIC_LAYER;

    const formattedDynamicPatterns = dynamicPatterns.map((p, i) => 
        `${FEW_SHOT_EXAMPLES.trim().split('\n\n').length + i + 1}. User asks: "${p.user_question}"\n   SQL:\n   ${p.successful_sql_query}`
    ).join('\n\n');

    const aiModel = config.ai.model;

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
        logger.error("Generated SQL failed validation:", validationOutput.correction);
        throw new Error(`The generated query was invalid. Reason: ${validationOutput.correction}`);
    }

    // Pipeline Step 3: Execute Query with Error Recovery
    logger.info(`[Audit Trail] Executing validated SQL for company ${companyId}: "${sqlQuery}"`);
    let { data: queryData, error: queryError } = await supabaseAdmin.rpc('execute_dynamic_query', {
      query_text: sqlQuery.replace(/;/g, '')
    });
    
    // Pipeline Step 3b: Error Recovery (if needed)
    if (queryError) {
        logger.warn(`[UniversalChat:Flow] Initial query failed: "${queryError.message}". Attempting recovery...`);
        
        const { output: recoveryOutput } = await errorRecoveryPrompt(
            { userQuery, failedQuery: sqlQuery, errorMessage: queryError.message, dbSchema: formattedSchema },
            { model: aiModel }
        );

        if (recoveryOutput?.correctedQuery) {
            logger.info(`[UniversalChat:Flow] AI provided a corrected query. Reasoning: ${recoveryOutput.reasoning}`);
            
            // Retry with the new query
            sqlQuery = recoveryOutput.correctedQuery; // Update the query to the corrected one
            
            // Re-validate the corrected query before executing
            const { output: revalidationOutput } = await queryValidationPrompt({ userQuery, sqlQuery }, { model: aiModel });
            if (!revalidationOutput?.isValid) {
                logger.error("Corrected SQL failed re-validation:", revalidationOutput.correction);
                throw new Error(`The AI's attempt to fix the query was also invalid. Reason: ${revalidationOutput.correction}`);
            }

            logger.info(`[Audit Trail] Executing re-validated SQL for company ${companyId}: "${sqlQuery}"`);
            const retryResult = await supabaseAdmin.rpc('execute_dynamic_query', {
                query_text: sqlQuery.replace(/;/g, '')
            });
            
            queryData = retryResult.data;
            queryError = retryResult.error;

            if (queryError) {
                logger.error('[UniversalChat:Flow] Corrected query also failed:', queryError.message);
                throw new Error(`I tried to automatically fix a query error, but the correction also failed. The original error was: ${queryError.message}`);
            } else {
                logger.info('[UniversalChat:Flow] Corrected query executed successfully.');
            }
        } else {
            logger.error('[UniversalChat:Flow] AI could not recover from the query error.');
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
    
    logger.info(`[UniversalChat:Flow] AI Confidence for query "${userQuery}": ${finalOutput.confidence}`);
    if (finalOutput.assumptions && finalOutput.assumptions.length > 0) {
        logger.info(`[UniversalChat:Flow] AI Assumptions: ${finalOutput.assumptions.join(', ')}`);
    }

    return {
        ...finalOutput,
        data: queryData || [],
    };
  }
);

export const universalChatFlow = universalChatOrchestrator;
