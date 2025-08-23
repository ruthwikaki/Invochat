'use server';
/**
 * @fileOverview Economic Impact Analysis Flow - Provides comprehensive business impact assessment
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { 
  getGrossMarginAnalysisFromDB, 
  getInventoryTurnoverAnalysisFromDB
} from '@/services/database';
import { logError } from '@/lib/error-handler';
import { config } from '@/config/app-config';

const EconomicImpactInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to analyze economic impact for."),
  scenarioType: z.enum(['pricing_optimization', 'inventory_reduction', 'new_product_launch', 'market_expansion', 'cost_reduction']).describe("Type of economic scenario to analyze."),
  parameters: z.object({
    priceChangePercent: z.number().optional().describe("Percentage change in pricing (positive for increase, negative for decrease)."),
    inventoryReductionPercent: z.number().optional().describe("Percentage reduction in inventory levels."),
    newProductCount: z.number().optional().describe("Number of new products to launch."),
    marketExpansionPercent: z.number().optional().describe("Percentage increase in market reach."),
    costReductionPercent: z.number().optional().describe("Percentage reduction in operational costs."),
  }).describe("Scenario-specific parameters for impact analysis."),
});

const EconomicImpactSchema = z.object({
  scenario: z.string().describe("Description of the economic scenario analyzed."),
  revenueImpact: z.object({
    currentRevenue: z.number().describe("Current monthly revenue estimate."),
    projectedRevenue: z.number().describe("Projected monthly revenue after changes."),
    revenueChange: z.number().describe("Absolute change in monthly revenue."),
    revenueChangePercent: z.number().describe("Percentage change in revenue."),
  }).describe("Revenue impact analysis."),
  profitabilityImpact: z.object({
    currentProfit: z.number().describe("Current monthly profit estimate."),
    projectedProfit: z.number().describe("Projected monthly profit after changes."),
    profitChange: z.number().describe("Absolute change in monthly profit."),
    profitChangePercent: z.number().describe("Percentage change in profit."),
    marginImpact: z.number().describe("Change in profit margin percentage."),
  }).describe("Profitability impact analysis."),
  operationalImpact: z.object({
    inventoryTurnover: z.number().describe("Impact on inventory turnover ratio."),
    cashFlowImprovement: z.number().describe("Estimated monthly cash flow improvement."),
    operationalEfficiency: z.number().describe("Percentage improvement in operational efficiency."),
  }).describe("Operational efficiency impact."),
  riskAssessment: z.object({
    riskLevel: z.enum(['low', 'medium', 'high']).describe("Overall risk level of the scenario."),
    keyRisks: z.array(z.string()).describe("Primary risk factors to consider."),
    mitigationStrategies: z.array(z.string()).describe("Recommended risk mitigation strategies."),
  }).describe("Risk assessment and mitigation."),
  timeframe: z.object({
    shortTerm: z.string().describe("Expected impact in 1-3 months."),
    mediumTerm: z.string().describe("Expected impact in 3-12 months."),
    longTerm: z.string().describe("Expected impact in 12+ months."),
  }).describe("Timeline for impact realization."),
  recommendations: z.array(z.string()).describe("Strategic recommendations for implementation."),
  confidence: z.number().min(0).max(100).describe("Confidence level in the analysis (0-100%)."),
});

const EconomicImpactOutputSchema = z.object({
  analysis: EconomicImpactSchema,
  comparativeScenarios: z.array(z.object({
    name: z.string(),
    revenueImpact: z.number(),
    profitImpact: z.number(),
    riskLevel: z.string(),
  })).describe("Alternative scenarios for comparison."),
  executiveSummary: z.string().describe("High-level summary for executive decision making."),
});

const economicImpactPrompt = ai.definePrompt({
  name: 'economicImpactPrompt',
  input: {
    schema: z.object({
      scenarioType: z.string(),
      parameters: z.object({}).passthrough(),
      currentMetrics: z.object({
        monthlyRevenue: z.number(),
        grossMargin: z.number(),
        inventoryTurnover: z.number(),
        averageOrderValue: z.number(),
      }),
      marketData: z.object({
        competitorPricing: z.number().optional(),
        marketGrowthRate: z.number().optional(),
        seasonalFactors: z.array(z.string()).optional(),
      }),
    }),
  },
  output: { schema: EconomicImpactOutputSchema },
  prompt: `
    You are a senior business analyst specializing in economic impact assessment. Analyze the following business scenario and provide a comprehensive economic impact analysis.

    **Scenario Type:** {{scenarioType}}
    **Parameters:** {{{json parameters}}}
    **Current Business Metrics:**
    {{{json currentMetrics}}}
    **Market Context:**
    {{{json marketData}}}

    **Your Analysis Should Include:**

    1. **Revenue Impact Analysis:**
       - Calculate realistic revenue projections based on the scenario
       - Consider market dynamics, demand elasticity, and competitive factors
       - Provide both absolute and percentage changes

    2. **Profitability Assessment:**
       - Analyze impact on gross and net profit margins
       - Consider cost structure changes and operational efficiency
       - Factor in implementation costs and ongoing expenses

    3. **Operational Impact:**
       - Assess changes to inventory turnover and cash flow
       - Evaluate operational efficiency improvements
       - Consider resource allocation and capacity implications

    4. **Risk Analysis:**
       - Identify key business risks and market uncertainties
       - Assess probability and potential impact of risks
       - Provide practical mitigation strategies

    5. **Timeline Projections:**
       - Short-term impacts (1-3 months)
       - Medium-term impacts (3-12 months)
       - Long-term strategic implications (12+ months)

    6. **Strategic Recommendations:**
       - Prioritized action items for implementation
       - Key performance indicators to monitor
       - Success criteria and milestones

    7. **Comparative Analysis:**
       - Generate 2-3 alternative scenarios for comparison
       - Highlight trade-offs and opportunity costs

    **Guidelines:**
    - Use realistic assumptions based on industry standards
    - Consider both optimistic and conservative scenarios
    - Focus on actionable insights for business decision-making
    - Provide quantified impacts wherever possible
    - Include confidence levels for your projections

    Provide your analysis in the specified JSON format with detailed explanations and practical recommendations.
  `,
});

export const economicImpactFlow = ai.defineFlow(
  {
    name: 'economicImpactFlow',
    inputSchema: EconomicImpactInputSchema,
    outputSchema: EconomicImpactOutputSchema,
  },
  async ({ companyId, scenarioType, parameters }) => {
    // Mock response for testing to avoid API quota issues
    if (process.env.MOCK_AI === 'true') {
      return {
        analysis: {
          scenario: `${scenarioType.replace('_', ' ')} scenario analysis`,
          revenueImpact: {
            currentRevenue: 125000,
            projectedRevenue: 143750,
            revenueChange: 18750,
            revenueChangePercent: 15.0,
          },
          profitabilityImpact: {
            currentProfit: 37500,
            projectedProfit: 46125,
            profitChange: 8625,
            profitChangePercent: 23.0,
            marginImpact: 2.5,
          },
          operationalImpact: {
            inventoryTurnover: 1.2,
            cashFlowImprovement: 12500,
            operationalEfficiency: 15.0,
          },
          riskAssessment: {
            riskLevel: 'medium' as const,
            keyRisks: [
              'Market demand uncertainty',
              'Competitive response risk',
              'Implementation complexity'
            ],
            mitigationStrategies: [
              'Phased rollout approach',
              'Continuous market monitoring',
              'Flexible pricing strategy'
            ],
          },
          timeframe: {
            shortTerm: 'Initial positive impact expected with 10-15% improvement',
            mediumTerm: 'Full benefits realized with sustained growth trajectory',
            longTerm: 'Market position strengthened with competitive advantages',
          },
          recommendations: [
            'Begin with pilot implementation in high-performing segments',
            'Establish robust KPI monitoring system',
            'Prepare contingency plans for various market scenarios',
            'Invest in supporting infrastructure and training'
          ],
          confidence: 78,
        },
        comparativeScenarios: [
          {
            name: 'Conservative Approach',
            revenueImpact: 12500,
            profitImpact: 5625,
            riskLevel: 'low',
          },
          {
            name: 'Aggressive Strategy',
            revenueImpact: 25000,
            profitImpact: 11250,
            riskLevel: 'high',
          },
        ],
        executiveSummary: `The ${scenarioType.replace('_', ' ')} scenario shows strong potential for business growth with manageable risks. Projected 15% revenue increase and 23% profit improvement justify the strategic investment. Recommend proceeding with phased implementation and continuous monitoring.`,
      };
    }

    try {
      // Gather current business metrics
      const [grossMarginData, inventoryTurnover] = await Promise.all([
        getGrossMarginAnalysisFromDB(companyId),
        getInventoryTurnoverAnalysisFromDB(companyId),
      ]);

      // Handle null cases and calculate current business metrics
      const safeGrossMarginData = grossMarginData || [];
      const safeInventoryTurnover = inventoryTurnover || [];

      const currentMetrics = {
        monthlyRevenue: safeGrossMarginData.reduce((sum, item) => sum + (item.revenue || 0), 0),
        grossMargin: safeGrossMarginData.length > 0 
          ? safeGrossMarginData.reduce((sum, item) => sum + (item.gross_margin_percentage || 0), 0) / safeGrossMarginData.length 
          : 0,
        inventoryTurnover: safeInventoryTurnover.length > 0 
          ? safeInventoryTurnover.reduce((sum, item) => sum + (item.turnover_ratio || 0), 0) / safeInventoryTurnover.length 
          : 0,
        averageOrderValue: safeGrossMarginData.length > 0 
          ? safeGrossMarginData.reduce((sum, item) => sum + (item.revenue || 0), 0) / Math.max(1, safeGrossMarginData.reduce((sum, item) => sum + (item.quantity_sold || 0), 0))
          : 0,
      };

      // Market context (simplified for now)
      const marketData = {
        competitorPricing: currentMetrics.averageOrderValue * 1.1, // Estimate 10% higher
        marketGrowthRate: 5.5, // Industry average
        seasonalFactors: ['Q4 holiday boost', 'Summer slowdown', 'Back-to-school surge'],
      };

      const { output } = await economicImpactPrompt({
        scenarioType,
        parameters,
        currentMetrics,
        marketData,
      }, { model: config.ai.model });

      if (!output) {
        throw new Error("AI failed to generate economic impact analysis.");
      }

      return output;
    } catch (e) {
      logError(e, { context: `[Economic Impact Flow] Failed for company ${companyId}, scenario: ${scenarioType}` });
      throw new Error("An error occurred while generating economic impact analysis.");
    }
  }
);

// Define a tool that wraps the flow
export const getEconomicImpact = ai.defineTool(
  {
    name: 'getEconomicImpact',
    description: "Analyzes the economic impact of business scenarios like pricing changes, inventory optimization, or market expansion. Use this for strategic business planning and ROI analysis.",
    inputSchema: EconomicImpactInputSchema,
    outputSchema: EconomicImpactOutputSchema
  },
  async (input) => economicImpactFlow(input)
);
