
'use server';
/**
 * @fileoverview Implements the advanced, multi-agent AI chat system for InvoChat.
 * This system uses a Chain-of-Thought approach with distinct steps for planning,
 * generation, validation, and response formulation to provide more accurate and
 * context-aware answers.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import type { UniversalChatInput, UniversalChatOutput } from '@/types/ai-schemas';
import { UniversalChatInputSchema, UniversalChatOutputSchema } from '@/types/ai-schemas';
import { getDbSchemaAndData, getQueryPatternsForCompany, saveSuccessfulQuery, getSettings } from '@/services/database';
import { config } from '@/config/app-config';
import { logger } from '@/lib/logger';
import { getEconomicIndicators } from './economic-tool';
import { getReorderSuggestions } from './reorder-tool';
import { getSupplierPerformanceReport } from './supplier-performance-tool';
import { createPurchaseOrdersTool } from './create-po-tool';
import { getDeadStockReport } from './dead-stock-tool';
import { getInventoryTurnoverReport } from './inventory-turnover-tool';
import { logError } from '@/lib/error-handler';

const UUID_REGEX = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * A robust and secure utility to substitute named parameters in a SQL query.
 *
 * It performs two critical functions:
 * 1.  Injects a mandatory, validated `company_id` into the query.
 * 2.  Safely substitutes any other named parameters (e.g., :productName) with
 *     values from the `params` object. It escapes single quotes in these values
 *     to prevent SQL injection.
 *
 * @param query The SQL query with named parameters (e.g., :company_id, :productName).
 * @param params An object where keys match the parameter names. Must include `companyId`.
 * @returns A final, safe SQL string ready for execution.
 * @throws {Error} if `companyId` is missing/invalid or if parameters are mismatched.
 */
function parameterizeQuery(query: string, params: Record<string, unknown>): string {
  let parameterizedQuery = query;

  // 1. Handle the mandatory company_id parameter first.
  if (!params.companyId || typeof params.companyId !== 'string' || !UUID_REGEX.test(params.companyId)) {
    throw new Error(`[Security] Invalid or missing companyId for parameterization.`);
  }
  parameterizedQuery = parameterizedQuery.replace(/:company_id/g, `'${params.companyId}'`);
  
  // 2. Handle all other dynamic parameters provided by the AI.
  const placeholders = query.match(/:[a-zA-Z0-9_]+/g) || [];
  const dynamicPlaceholders = placeholders.filter(p => p !== ':company_id');

  for (const placeholder of dynamicPlaceholders) {
    const paramName = placeholder.substring(1); // Remove the leading ':'
    
    if (!(paramName in params)) {
      throw new Error(`[Security] Mismatch: SQL query expected parameter '${placeholder}' but it was not provided.`);
    }
    
    const value = params[paramName];
    let sanitizedValue: string;

    // Sanitize and format the value based on its type.
    if (typeof value === 'string') {
      // Escape single quotes for SQL and wrap in single quotes.
      sanitizedValue = `'${value.replace(/'/g, "''")}'`;
    } else if (typeof value === 'number') {
      sanitizedValue = String(value);
    } else if (value === null || value === undefined) {
      sanitizedValue = 'NULL';
    } else {
        throw new Error(`[Security] Unsupported parameter type for '${placeholder}': ${typeof value}`);
    }
    
    // Replace all occurrences of the placeholder with the sanitized value.
    parameterizedQuery = parameterizedQuery.replace(new RegExp(placeholder, 'g'), sanitizedValue);
  }

  // 3. Final security check: ensure no placeholders are left unreplaced.
  const remainingPlaceholders = parameterizedQuery.match(/:[a-zA-Z0-9_]+/g);
  if (remainingPlaceholders) {
    throw new Error(`[Security] Query contains unreplaced parameters: ${remainingPlaceholders.join(', ')}`);
  }

  return parameterizedQuery;
}


const ENHANCED_SEMANTIC_LAYER = `
  E-COMMERCE & INVENTORY CONCEPTS:
  - "Landed Cost": The total cost of a product (cost + shipping + taxes). Use the 'landed_cost' field from the inventory table.
  - "On Order Quantity": Units of an item that have been ordered from a supplier but not yet received. Use 'on_order_quantity'.
  - "Sales Channel": Where the sale originated (e.g., 'shopify', 'amazon', 'manual'). Use the 'sales_channel' field in the 'orders' table.
  - "Reordering": The process of ordering more stock. Use the 'getReorderSuggestions' tool to determine what needs to be ordered.
  - "Profit Margin": Calculation of profitability. Can be Gross Margin or Net Margin.

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
  - "Gross margin": (Revenue - COGS) / Revenue. Use (selling_price - landed_cost) / selling_price.
  - "Net Margin": The profit after subtracting sales channel fees. It is calculated by first determining Gross Margin for a sale, then subtracting any 'percentage_fee' and 'fixed_fee' from the 'channel_fees' table for the corresponding 'sales_channel'.
  - "Operating margin": Operating Income / Revenue
  - "Cash conversion cycle": DSI + Days Sales Outstanding - Days Payable Outstanding
  - "Working capital": Current Assets - Current Liabilities
  - "Return on assets (ROA)": Net Income / Total Assets
`;

const BUSINESS_QUERY_EXAMPLES = `
  4. Forecasting Query:
     User: "Forecast next month's demand for my top 10 products"
     SQL: WITH historical_sales AS (
       SELECT oi.sku as sku, 
              DATE_TRUNC('month', o.sale_date) as month,
              SUM(oi.quantity) as monthly_quantity
       FROM order_items oi
       JOIN orders o ON oi.sale_id = o.id
       WHERE o.company_id = :company_id
         AND o.sale_date >= CURRENT_DATE - INTERVAL '12 months'
       GROUP BY oi.sku, month
     ),
     trend_analysis AS (
       SELECT sku,
              REGR_SLOPE(monthly_quantity, EXTRACT(epoch FROM month)) as trend,
              REGR_INTERCEPT(monthly_quantity, EXTRACT(epoch FROM month)) as base,
              AVG(monthly_quantity) as avg_monthly,
              STDDEV(monthly_quantity) as stddev_monthly
       FROM historical_sales
       GROUP BY sku
     ),
     SELECT t.sku, 
            i.name as product_name,
            ROUND(t.base + t.trend * EXTRACT(epoch FROM DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month')))) as forecasted_quantity,
            t.avg_monthly as historical_average,
            ROUND(t.stddev_monthly) as demand_variability
     FROM trend_analysis t
     JOIN inventory i ON t.sku = i.sku AND i.company_id = :company_id
     ORDER BY t.avg_monthly DESC
     LIMIT 10;

  5. ABC Analysis Query:
     User: "Perform ABC analysis on my inventory"
     SQL: WITH product_revenue AS (
       SELECT i.sku,
              i.name as product_name,
              SUM(oi.quantity * oi.unit_price) as total_revenue,
              SUM(oi.quantity) as total_units
       FROM inventory i
       JOIN order_items oi ON i.sku = oi.sku
       JOIN orders o ON oi.sale_id = o.id
       WHERE i.company_id = :company_id AND o.company_id = :company_id
         AND o.sale_date >= CURRENT_DATE - INTERVAL '12 months'
       GROUP BY i.sku, i.name
     ),
     revenue_ranking AS (
       SELECT *,
              SUM(total_revenue) OVER (ORDER BY total_revenue DESC) as cumulative_revenue,
              SUM(total_revenue) OVER () as grand_total_revenue,
              ROW_NUMBER() OVER (ORDER BY total_revenue DESC) as rank
       FROM product_revenue
     ),
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

  6. Profit Margin Analysis Query:
     User: "Analyze my gross profit margins by product and sales channel"
     SQL:
     WITH product_sales AS (
       SELECT
         i.name as product_name,
         o.sales_channel,
         oi.unit_price as selling_price,
         COALESCE(i.landed_cost, i.cost) as cost_of_good,
         oi.quantity
       FROM order_items oi
       JOIN orders o ON oi.sale_id = o.id
       JOIN inventory i ON oi.sku = i.sku AND i.company_id = o.company_id
       WHERE o.company_id = :company_id
         AND o.sale_date >= CURRENT_DATE - INTERVAL '90 days'
         AND oi.unit_price > 0
     )
     SELECT
       product_name,
       COALESCE(sales_channel, 'Unknown') as sales_channel,
       SUM(selling_price * quantity) as total_revenue,
       SUM(cost_of_good * quantity) as total_cogs,
       AVG((selling_price - cost_of_good) / NULLIF(selling_price, 0)) * 100 as avg_gross_margin_percentage
     FROM product_sales
     GROUP BY product_name, sales_channel
     ORDER BY total_revenue DESC;

  7. Net Margin Analysis by Channel:
     User: "What is my net margin for Shopify sales?"
     SQL:
     WITH sales_with_costs AS (
        SELECT
            o.sales_channel,
            oi.unit_price as selling_price,
            oi.quantity,
            COALESCE(i.landed_cost, i.cost) as cost_of_good
        FROM order_items oi
        JOIN orders o ON oi.sale_id = o.id
        JOIN inventory i ON oi.sku = i.sku AND i.company_id = o.company_id
        WHERE o.company_id = :company_id
          AND o.platform = 'shopify' -- Use platform for filtering
          AND o.sale_date >= CURRENT_DATE - INTERVAL '90 days'
          AND oi.unit_price > 0
     ),
     channel_fees AS (
        SELECT percentage_fee, fixed_fee
        FROM channel_fees
        WHERE company_id = :company_id AND channel_name = 'Shopify'
        LIMIT 1
     ),
     profit_calc AS (
        SELECT
            SUM(s.selling_price * s.quantity) as total_revenue,
            SUM(s.cost_of_good * s.quantity) as total_cogs,
            -- Calculate total fees based on a percentage of revenue plus a fixed fee per transaction
            (SUM(s.selling_price * s.quantity) * COALESCE((SELECT percentage_fee FROM channel_fees), 0)) + (COUNT(*) * COALESCE((SELECT fixed_fee FROM channel_fees), 0)) as total_fees
        FROM sales_with_costs s
     )
     SELECT
        p.total_revenue,
        p.total_cogs,
        p.total_fees,
        (p.total_revenue - p.total_cogs - p.total_fees) as net_profit,
        CASE
            WHEN p.total_revenue > 0 THEN ((p.total_revenue - p.total_cogs - p.total_fees) / p.total_revenue) * 100
            ELSE 0
        END as net_margin_percentage
     FROM profit_calc p;

  8. Margin Trend Analysis over Time:
     User: "Show me my margin trends over the last year"
     SQL:
     WITH monthly_sales AS (
       SELECT
         DATE_TRUNC('month', o.sale_date) as sales_month,
         SUM(oi.unit_price * oi.quantity) as total_revenue,
         SUM(COALESCE(i.landed_cost, i.cost) * oi.quantity) as total_cogs
       FROM order_items oi
       JOIN orders o ON oi.sale_id = o.id
       JOIN inventory i ON oi.sku = i.sku AND i.company_id = o.company_id
       WHERE o.company_id = :company_id
         AND o.sale_date >= CURRENT_DATE - INTERVAL '12 months'
         AND oi.unit_price > 0
       GROUP BY sales_month
     )
     SELECT
       TO_CHAR(sales_month, 'YYYY-MM') as month,
       total_revenue,
       total_cogs,
       CASE
         WHEN total_revenue > 0 THEN ((total_revenue - total_cogs) / total_revenue) * 100
         ELSE 0
       END as gross_margin_percentage
     FROM monthly_sales
     ORDER BY sales_month;
`;


const FEW_SHOT_EXAMPLES = `
  1. User asks: "Who were my top 5 customers last month?"
     SQL:
     SELECT
        c.customer_name as name,
        SUM(s.total_amount) as total_spent
     FROM orders s
     JOIN customers c ON s.customer_id = c.id
     WHERE s.company_id = :company_id
       AND s.sale_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
       AND s.sale_date < date_trunc('month', CURRENT_DATE)
     GROUP BY c.customer_name
     ORDER BY total_spent DESC
     LIMIT 5;

  2. User asks: "What was my return rate last month?"
     SQL:
     WITH MonthlySales AS (
         SELECT COUNT(id) as total_sales
         FROM orders
         WHERE company_id = :company_id
           AND sale_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
           AND sale_date < date_trunc('month', CURRENT_DATE)
     ),
     MonthlyReturns AS (
         SELECT COUNT(id) as total_returns
         FROM returns
         WHERE company_id = :company_id
           AND requested_at >= date_trunc('month', CURRENT_DATE) - INTERVAL '1 month'
           AND requested_at < date_trunc('month', CURRENT_DATE)
     )
     SELECT
        ms.total_sales,
        mr.total_returns,
        (mr.total_returns::decimal / ms.total_sales) * 100 as return_rate_percentage
     FROM MonthlySales ms, MonthlyReturns mr;

  3. User asks: "What was my total inventory value in the 'Main Warehouse'?"
     User input found: warehouseName = 'Main Warehouse'
     SQL:
     SELECT SUM(i.quantity * i.cost) as total_inventory_value
     FROM inventory i
     JOIN locations l ON i.location_id = l.id
     WHERE i.company_id = :company_id
       AND l.name = :warehouseName;

  ${BUSINESS_QUERY_EXAMPLES}
`;

const tools = [getEconomicIndicators, getReorderSuggestions, getSupplierPerformanceReport, createPurchaseOrdersTool, getDeadStockReport, getInventoryTurnoverReport];

const SqlGenerationOutputSchema = z.object({
  sqlQuery: z.string().optional().describe('The generated SQL query, using named placeholders (e.g., :paramName) for user-provided values.'),
  parameters: z.record(z.string(), z.union([z.string(), z.number()])).optional().describe('An object mapping placeholder names from the query to their actual values.'),
  reasoning: z.string().describe('A brief explanation of the query logic.'),
});


const sqlGenerationPrompt = ai.definePrompt({
  name: 'sqlGenerationPrompt',
  input: { schema: z.object({ userQuery: z.string(), dbSchema: z.string(), semanticLayer: z.string(), dynamicExamples: z.string(), companyId: z.string().uuid() }) },
  output: { schema: SqlGenerationOutputSchema },
  tools,
  prompt: `
    You are an expert PostgreSQL query generation agent for an e-commerce analytics system. Your primary function is to translate a user's natural language question into a secure, efficient, and advanced SQL query. You also have access to tools for questions that cannot be answered from the database.

    IMPORTANT CONTEXT:
    - The current user's Company ID is: {{{companyId}}}
    - When calling a tool that requires a companyId, you MUST use this value.
    - When generating SQL, you MUST use the placeholder ':company_id'. This will be handled automatically.

    DATABASE SCHEMA OVERVIEW:
    {{{dbSchema}}}

    SEMANTIC LAYER (Business Definitions):
    {{{semanticLayer}}}

    USER'S QUESTION: "{{userQuery}}"

    **QUERY GENERATION PROCESS (You MUST follow these steps):**

    **A) For ALL Queries (NON-NEGOTIABLE SECURITY RULES):**
    1.  **Security is PARAMOUNT**: Your primary security responsibility is to **NEVER** inline user-provided text (like product names, categories, or warehouse names) directly into the SQL query string. You **MUST** use a named placeholder (e.g., \`:warehouseName\`, \`:productSku\`).
    2.  **Mandatory Filtering**: Every table referenced (including in joins and subqueries) MUST include a \`WHERE\` clause filtering by the user's company using a placeholder: \`company_id = :company_id\`. This is a non-negotiable security requirement.
    3.  **Output Structure**: Your output must contain the \`sqlQuery\` with placeholders, and a separate \`parameters\` object mapping each placeholder name (without the colon) to its value.
    4.  **Column Verification**: Before using a column, verify it exists in the respective table by checking the DATABASE SCHEMA OVERVIEW. Do not hallucinate column names.
    5.  **NO SQL Comments**: The final query MUST NOT contain any SQL comments (e.g., --, /* */).
    6.  **Syntax**: Use PostgreSQL syntax, like \`(CURRENT_DATE - INTERVAL '90 days')\` for date math.
    7.  **NO Cross Joins**: ALWAYS specify a valid JOIN condition using \`ON\`.

    **B) For COMPLEX ANALYTICAL Queries:**
    8.  **Advanced SQL is MANDATORY**: Use advanced SQL features like CTEs and Window Functions for readability and correctness.

    **C) For QUESTIONS THAT REQUIRE TOOLS:**
    9.  **Inventory Reordering**: If the user asks what to reorder, which products are low on stock, or to create a purchase order, you MUST use the \`getReorderSuggestions\` tool.
    10. **Economic Questions**: If the user's question is about a general economic indicator (like inflation, GDP, etc.) that is NOT in their database, you MUST use the \`getEconomicIndicators\` tool.
    11. **Supplier Performance**: If the user asks about supplier reliability, on-time delivery, or which supplier is 'best', you MUST use the \`getSupplierPerformanceReport\` tool.
    12. **Creating Purchase Orders**: If you have just presented the user with reorder suggestions (via the 'getReorderSuggestions' tool) and they confirm they want to proceed, you MUST use the \`createPurchaseOrdersFromSuggestions\` tool, passing the suggestions from the conversation history into the tool's 'suggestions' parameter.
    13. **Dead Stock**: If the user asks about 'dead stock', 'unsold items', 'stale inventory', or 'slow-moving products', you MUST use the \`getDeadStockReport\` tool.
    14. **Inventory Turnover**: If the user asks about 'inventory turnover rate', 'stock turn', or how efficiently they are selling through stock, you MUST use the \`getInventoryTurnoverReport\` tool.
    
    **Step 3: Consult Examples for Structure.**
    Review these examples to understand the expected query style and placeholder usage.
    ---
    COMPANY-SPECIFIC EXAMPLES (Highest Priority):
    {{{dynamicExamples}}}
    ---
    ---
    FEW-SHOT EXAMPLES (General Fallback):
    ${FEW_SHOT_EXAMPLES}
    ---

    **Step 4: Generate the Response.**
    Based on the analysis, rules, and examples, decide the best course of action.
    - If the question can be answered with SQL, generate the query and the parameters object.
    - If the question requires a tool, call the appropriate tool.
    - Your response MUST conform to the JSON output schema.
  `,
});

const queryValidationPrompt = ai.definePrompt({
  name: 'queryValidationPrompt',
  input: { schema: z.object({ userQuery: z.string(), sqlQuery: z.string() }) },
  output: { schema: z.object({ isValid: z.boolean(), correction: z.string().optional().describe('Reason if invalid.') }) },
  prompt: `
    You are a SQL validation agent. Review the generated SQL query with EXTREME SCRUTINY. Your primary job is to prevent any unsafe or incorrect queries from executing.

    USER'S QUESTION: "{{userQuery}}"
    GENERATED SQL (with placeholders): \`\`\`sql
{{sqlQuery}}
\`\`\`

    **SECURITY VALIDATION CHECKLIST (FAIL THE QUERY IF ANY OF THESE ARE TRUE):**
    1.  **Check for Forbidden Keywords**: Does the query contain ANY of the following keywords (case-insensitive)?
        - \`INSERT\`, \`UPDATE\`, \`DELETE\`, \`TRUNCATE\`, \`ALTER\`, \`GRANT\`, \`REVOKE\`, \`CREATE\`, \`EXECUTE\`
        If yes, FAIL validation immediately.
    2.  **Check for SQL Comments**: Does the query contain SQL comments (\`--\` or \`/*\`)?
        If yes, FAIL validation.
    3.  **Mandatory Company ID Filter**: Does EVERY table reference (including joins, subqueries, and CTEs) have a \`WHERE\` clause that filters by \`company_id\` (e.g., \`WHERE company_id = :company_id\`)?
        If even one is missing, FAIL validation.
    4.  **Read-Only Check**: Is the query a read-only \`SELECT\` statement?
        If it's anything else, FAIL validation.
    5.  **Check for Common Injection Patterns**: Does the query contain patterns indicative of SQL injection attacks, such as \`'1'='1'\`, \`UNION SELECT\`, or execution of commands like \`pg_sleep\`?
        If yes, FAIL validation immediately.

    **LOGIC & CORRECTNESS CHECKLIST:**
    6.  **Syntax Validity**: Is the syntax valid for PostgreSQL?
    7.  **Logical Answer**: Does the query logically answer the user's question?
    8.  **Business Sense**: Does it use the correct columns/tables based on the question and business context?

    **OUTPUT FORMAT:**
    - If ALL security and logic checks pass, return \`{"isValid": true}\`.
    - If ANY check fails, return \`{"isValid": false, "correction": "Explain the specific reason for failure concisely and technically."}\`.
  `,
});

const errorRecoveryPrompt = ai.definePrompt({
    name: 'errorRecoveryPrompt',
    input: { schema: z.object({ userQuery: z.string(), failedQuery: z.string(), errorMessage: z.string(), dbSchema: z.string() }) },
    output: { schema: z.object({ correctedQuery: z.string().optional().describe('The corrected SQL query, if fixable.'), reasoning: z.string().describe('Explanation of the error and the fix.') }) },
    prompt: `
        You are an expert SQL debugging agent. Your task is to analyze a failed PostgreSQL query and its error message, then provide a corrected query.

        DATABASE SCHEMA FOR REFERENCE:
        {{{dbSchema}}}

        USER'S ORIGINAL QUESTION: "{{userQuery}}"

        FAILED SQL QUERY (Note: this is the version with the placeholders):
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
        5.  **If Unfixable**: If the error is ambiguous or you cannot confidently fix it, do not provide a \`correctedQuery\`. Explain why in the \`reasoning\` field instead.
        6.  **Security**: The corrected query must still be a read-only SELECT statement and must contain the company_id filter (\`WHERE company_id = :company_id\`) on all tables. It must not contain SQL comments.
    `,
});

const FinalResponseObjectSchema = UniversalChatOutputSchema.omit({ data: true, toolName: true });
const finalResponsePrompt = ai.definePrompt({
  name: 'finalResponsePrompt',
  input: { schema: z.object({ userQuery: z.string(), queryDataJson: z.string() }) },
  output: { schema: FinalResponseObjectSchema },
  prompt: `
    You are InvoChat, an expert AI inventory analyst.
    The user asked: "{{userQuery}}"
    You have executed a database query or tool and received this JSON data:
    {{{queryDataJson}}}

    YOUR TASK:
    1.  **Analyze Data**:
        - Review the JSON data. If it's empty or null, state that you found no information.
        - **Special Case:** If the JSON data contains a "createdPoCount" key, your main task is to confirm the action. Your response should be a success message, for example: "Done! I've created 2 new purchase orders. You can view them on the Purchase Orders page." In this case, you should also suggest a 'none' visualization type.
        - Your analysis should be based *only* on the data provided.
    2.  **Formulate Response**:
        - Provide a concise, natural language response based on the database data.
        - Do NOT mention SQL, databases, or JSON.
    3.  **Assess Confidence**: Based on the user's query and the data, provide a confidence score from 0.0 to 1.0. A 1.0 means you are certain the query fully answered the user's request. A lower score means you had to make assumptions.
    4.  **List Assumptions**: If your confidence is below 1.0, list the assumptions you made (e.g., "Interpreted 'top products' as 'top by sales value'"). If confidence is 1.0, return an empty array.
    5.  **Suggest Visualization**: Based on the data's structure, suggest a visualization type and a title for it. Available types are: 'table', 'bar', 'pie', 'line', 'treemap', 'scatter', 'none'.
    6.  **Format Output**: Return a single JSON object with 'response', 'visualization', 'confidence', and 'assumptions' fields. Do NOT include the raw data in your response.
  `,
});

const universalChatOrchestrator = ai.defineFlow(
  {
    name: 'universalChatOrchestrator',
    inputSchema: UniversalChatInputSchema,
    outputSchema: UniversalChatOutputSchema,
  },
  async (input) => {
    const { companyId, conversationHistory } = input;
    const lastMessage = conversationHistory[conversationHistory.length - 1];
    const userQuery = lastMessage?.content[0]?.text || '';
    const supabaseAdmin = getServiceRoleClient();

    if (!userQuery) {
        throw new Error("User query was empty.");
    }
    
    const [schemaData, settings, dynamicPatterns] = await Promise.all([
        getDbSchemaAndData(companyId),
        getSettings(companyId),
        getQueryPatternsForCompany(companyId)
    ]);

    const formattedSchema = schemaData.map(table => 
        `Table: ${table.tableName} | Columns: ${table.rows.length > 0 ? Object.keys(table.rows[0]).join(', ') : 'No columns detected or table is empty'}`
    ).join('\n');
    
    const semanticLayer = ENHANCED_SEMANTIC_LAYER;

    const formattedDynamicPatterns = dynamicPatterns.length > 0 
        ? dynamicPatterns.map((p, i) => 
            `${FEW_SHOT_EXAMPLES.trim().split('\n\n').length + i + 1}. User asks: "${p.user_question}"\n   SQL:\n   ${p.successful_sql_query}`
          ).join('\n\n')
        : "No company-specific examples found yet. Rely on the general examples.";

    const aiModel = config.ai.model;
    
    const { output: generationOutput, toolCalls } = await ai.generate({
      model: aiModel,
      prompt: sqlGenerationPrompt,
      input: { userQuery, dbSchema: formattedSchema, semanticLayer, dynamicExamples: formattedDynamicPatterns, companyId },
      history: conversationHistory.slice(0, -1) // Pass previous messages as history context
    });
    
    if (toolCalls && toolCalls.length > 0) {
        logger.info(`[UniversalChat:Flow] AI chose to use a tool: ${toolCalls[0].name}`);
        const toolCall = toolCalls[0];
        const toolResult = await ai.runTool(toolCall);
        
        const queryDataJson = JSON.stringify([toolResult.output]);
        
        const { output: finalOutput } = await finalResponsePrompt(
            { userQuery, queryDataJson },
            { model: aiModel }
        );

        if (!finalOutput) {
            throw new Error('The AI model did not return a valid final response object after tool use.');
        }
        
        return {
            ...finalOutput,
            data: toolResult.output as any[],
            toolName: toolCall.name,
        };
    }

    if (generationOutput?.sqlQuery) {
        let sqlQueryWithPlaceholder = generationOutput.sqlQuery;
        const sqlParameters = generationOutput.parameters || {};

        const { output: validationOutput } = await queryValidationPrompt(
            { userQuery, sqlQuery: sqlQueryWithPlaceholder },
            { model: aiModel }
        );
        if (!validationOutput?.isValid) {
            logger.error("Generated SQL failed validation:", validationOutput.correction);
            throw new Error(`The generated query was invalid. Reason: ${validationOutput.correction}`);
        }

        let finalSqlQuery = parameterizeQuery(sqlQueryWithPlaceholder, { ...sqlParameters, companyId });

        logger.info(`[Audit Trail] Executing validated SQL for company ${companyId}: "${finalSqlQuery}"`);

        const QUERY_TIMEOUT = 30000;
        let queryData: unknown[] | null = null;
        let queryError: { message: string } | null = null;

        try {
            const queryPromise = supabaseAdmin.rpc('execute_dynamic_query', {
              query_text: finalSqlQuery.replace(/;/g, '')
            });

            const timeoutPromise = new Promise<{data: null, error: Error}>((resolve) =>
                setTimeout(() => resolve({ data: null, error: new Error('Query timed out after 30 seconds.') }), QUERY_TIMEOUT)
            );

            const result = await Promise.race([queryPromise, timeoutPromise]);
            queryData = result.data;
            queryError = result.error;
        } catch(e) {
            logError(e, {context: 'Unexpected error during query execution with timeout'});
            queryError = e as Error;
        }

        
        if (queryError) {
            logger.warn(`[UniversalChat:Flow] Initial query failed: "${queryError.message}". Attempting recovery...`);
            
            const { output: recoveryOutput } = await errorRecoveryPrompt(
                { userQuery, failedQuery: sqlQueryWithPlaceholder, errorMessage: queryError.message, dbSchema: formattedSchema },
                { model: aiModel }
            );

            if (recoveryOutput?.correctedQuery) {
                logger.info(`[UniversalChat:Flow] AI provided a corrected query. Reasoning: ${recoveryOutput.reasoning}`);
                
                sqlQueryWithPlaceholder = recoveryOutput.correctedQuery;
                
                const { output: revalidationOutput } = await queryValidationPrompt({ userQuery, sqlQuery: sqlQueryWithPlaceholder }, { model: aiModel });
                if (!revalidationOutput?.isValid) {
                    logger.error("Corrected SQL failed re-validation:", revalidationOutput.correction);
                    throw new Error(`The AI's attempt to fix the query was also invalid. Reason: ${revalidationOutput.correction}`);
                }
                
                finalSqlQuery = parameterizeQuery(sqlQueryWithPlaceholder, { ...sqlParameters, companyId });

                logger.info(`[Audit Trail] Executing re-validated SQL for company ${companyId}: "${finalSqlQuery}"`);

                 try {
                    const retryQueryPromise = supabaseAdmin.rpc('execute_dynamic_query', {
                        query_text: finalSqlQuery.replace(/;/g, '')
                    });

                    const retryTimeoutPromise = new Promise<{data: null, error: Error}>((resolve) =>
                        setTimeout(() => resolve({ data: null, error: new Error('Query timed out after 30 seconds.') }), QUERY_TIMEOUT)
                    );
                    
                    const retryResult = await Promise.race([retryQueryPromise, retryTimeoutPromise]);
                    queryData = retryResult.data;
                    queryError = retryResult.error;
                } catch(e) {
                    logError(e, {context: 'Unexpected error during retry query execution with timeout'});
                    queryError = e as Error;
                }
                
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

        if (!queryError) {
            // Save the version of the query with the placeholder for safer re-use in examples.
            await saveSuccessfulQuery(companyId, userQuery, sqlQueryWithPlaceholder);
        }

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

    logger.warn("[UniversalChat:Flow] AI did not generate SQL or call a tool. Trying a direct answer.");
    const { text } = await ai.generate({
        model: aiModel,
        prompt: userQuery,
    });
    return {
        response: text,
        data: [],
        visualization: { type: 'none' },
        confidence: 0.5,
        assumptions: ['I was unable to answer this from your database and answered from general knowledge.'],
    };
  }
);

export const universalChatFlow = universalChatOrchestrator;
