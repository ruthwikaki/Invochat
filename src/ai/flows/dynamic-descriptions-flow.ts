'use server';
/**
 * @fileOverview Dynamic Product Descriptions Flow - AI-powered product description optimization
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';
import { getUnifiedInventoryFromDB } from '@/services/database';
import { logError } from '@/lib/error-handler';
import { config } from '@/config/app-config';

const DynamicDescriptionInputSchema = z.object({
  companyId: z.string().uuid().describe("The ID of the company to generate descriptions for."),
  productSku: z.string().optional().describe("Specific product SKU to generate description for (if not provided, will optimize multiple products)."),
  optimizationType: z.enum(['seo', 'conversion', 'brand', 'technical', 'emotional']).describe("Type of optimization to apply to descriptions."),
  targetAudience: z.enum(['general', 'technical', 'luxury', 'budget', 'business']).describe("Target audience for the descriptions."),
  tone: z.enum(['professional', 'casual', 'enthusiastic', 'authoritative', 'friendly']).describe("Tone of voice for the descriptions."),
  includeKeywords: z.array(z.string()).optional().describe("Specific keywords to include for SEO optimization."),
  maxLength: z.number().optional().default(300).describe("Maximum length for descriptions in characters."),
});

const ProductDescriptionSchema = z.object({
  sku: z.string().describe("Product SKU."),
  originalTitle: z.string().describe("Original product title."),
  optimizedTitle: z.string().describe("AI-optimized product title."),
  originalDescription: z.string().describe("Original product description."),
  optimizedDescription: z.string().describe("AI-optimized product description."),
  keyFeatures: z.array(z.string()).describe("Key features highlighted in the description."),
  seoKeywords: z.array(z.string()).describe("SEO keywords naturally integrated."),
  emotionalTriggers: z.array(z.string()).describe("Emotional triggers used to drive conversions."),
  uniqueSellingPoints: z.array(z.string()).describe("Unique selling propositions emphasized."),
  callToAction: z.string().describe("Recommended call-to-action for the product."),
  improvementScore: z.number().min(0).max(100).describe("Estimated improvement score over original (0-100%)."),
  targetAudienceMatch: z.number().min(0).max(100).describe("How well the description matches target audience (0-100%)."),
});

const DynamicDescriptionOutputSchema = z.object({
  optimizedProducts: z.array(ProductDescriptionSchema),
  overallStrategy: z.string().describe("Overall optimization strategy applied."),
  performanceProjections: z.object({
    estimatedConversionImprovement: z.number().describe("Estimated conversion rate improvement percentage."),
    seoImpact: z.string().describe("Expected SEO impact and search ranking improvements."),
    brandConsistency: z.number().min(0).max(100).describe("Brand consistency score across descriptions."),
  }).describe("Projected performance improvements."),
  implementationTips: z.array(z.string()).describe("Practical tips for implementing the optimized descriptions."),
  abTestRecommendations: z.array(z.string()).describe("A/B testing recommendations for validation."),
});

const dynamicDescriptionPrompt = ai.definePrompt({
  name: 'dynamicDescriptionPrompt',
  input: {
    schema: z.object({
      products: z.array(z.object({
        sku: z.string(),
        title: z.string(),
        description: z.string().nullable(),
        price: z.number().optional(),
        category: z.string().nullable(),
      })),
      optimizationType: z.string(),
      targetAudience: z.string(),
      tone: z.string(),
      includeKeywords: z.array(z.string()).optional(),
      maxLength: z.number(),
    }),
  },
  output: { schema: DynamicDescriptionOutputSchema },
  prompt: `
    You are an expert copywriter and digital marketing specialist. Your task is to create compelling, optimized product descriptions that drive conversions and improve search rankings.

    **Products to Optimize:**
    {{{json products}}}

    **Optimization Parameters:**
    - **Type:** {{optimizationType}}
    - **Target Audience:** {{targetAudience}}
    - **Tone:** {{tone}}
    - **Keywords to Include:** {{includeKeywords}}
    - **Max Length:** {{maxLength}} characters

    **Your Optimization Strategy:**

    1. **Title Optimization:**
       - Create compelling, keyword-rich titles that grab attention
       - Include primary benefits and unique selling points
       - Ensure titles are search-friendly and conversion-focused

    2. **Description Enhancement:**
       - Write engaging descriptions that tell a story
       - Highlight key features and benefits clearly
       - Include emotional triggers that resonate with {{targetAudience}}
       - Naturally integrate SEO keywords without keyword stuffing
       - Use persuasive language that drives action

    3. **Audience-Specific Optimization:**
       - **General:** Focus on universal benefits and clear value propositions
       - **Technical:** Include specifications, compatibility, and technical details
       - **Luxury:** Emphasize quality, exclusivity, and premium experience
       - **Budget:** Highlight value, savings, and practical benefits
       - **Business:** Focus on ROI, efficiency, and professional outcomes

    4. **Tone Implementation:**
       - **Professional:** Formal, credible, and authoritative language
       - **Casual:** Relaxed, conversational, and approachable tone
       - **Enthusiastic:** Energetic, exciting, and passion-driven language
       - **Authoritative:** Expert, confident, and trustworthy tone
       - **Friendly:** Warm, personal, and customer-focused approach

    5. **SEO Optimization:**
       - Research and include relevant long-tail keywords
       - Optimize for featured snippets and voice search
       - Create descriptions that answer common customer questions
       - Include semantic keywords and related terms

    6. **Conversion Optimization:**
       - Address common objections and concerns
       - Create urgency and scarcity where appropriate
       - Include social proof elements where relevant
       - End with strong, actionable calls-to-action

    **Quality Standards:**
    - Keep descriptions under {{maxLength}} characters
    - Ensure all claims are factual and supportable
    - Maintain brand consistency across all descriptions
    - Create unique, non-duplicate content for each product
    - Focus on customer benefits rather than just features

    **Performance Analysis:**
    - Estimate improvement potential for each product
    - Assess target audience alignment
    - Project SEO and conversion impacts
    - Provide implementation and testing recommendations

    Provide comprehensive optimization for each product in the specified JSON format.
  `,
});

export const dynamicDescriptionFlow = ai.defineFlow(
  {
    name: 'dynamicDescriptionFlow',
    inputSchema: DynamicDescriptionInputSchema,
    outputSchema: DynamicDescriptionOutputSchema,
  },
  async ({ companyId, productSku, optimizationType, targetAudience, tone, includeKeywords = [], maxLength }) => {
    // Mock response for testing to avoid API quota issues
    if (process.env.MOCK_AI === 'true') {
      return {
        optimizedProducts: [
          {
            sku: productSku || 'MOCK-PROD-001',
            originalTitle: 'Basic Widget',
            optimizedTitle: 'Premium Performance Widget - Professional Grade Solution',
            originalDescription: 'A simple widget for everyday use.',
            optimizedDescription: 'Transform your workflow with our premium performance widget. Engineered for professionals who demand excellence, this industry-leading solution delivers unmatched reliability and efficiency. Perfect for streamlining operations and boosting productivity.',
            keyFeatures: ['Premium quality', 'Professional grade', 'High performance', 'Reliable operation'],
            seoKeywords: ['premium widget', 'professional solution', 'workflow optimization'],
            emotionalTriggers: ['Transform your workflow', 'Demand excellence', 'Industry-leading'],
            uniqueSellingPoints: ['Unmatched reliability', 'Professional grade quality', 'Streamlined operations'],
            callToAction: 'Upgrade your productivity today - order now!',
            improvementScore: 85,
            targetAudienceMatch: 92,
          }
        ],
        overallStrategy: `Applied ${optimizationType} optimization with ${tone} tone targeting ${targetAudience} audience. Focus on conversion-driven copy with natural keyword integration.`,
        performanceProjections: {
          estimatedConversionImprovement: 25.5,
          seoImpact: 'Improved search rankings expected for targeted keywords with enhanced click-through rates',
          brandConsistency: 88,
        },
        implementationTips: [
          'A/B test optimized descriptions against originals',
          'Monitor keyword rankings and organic traffic',
          'Track conversion rate changes post-implementation',
          'Gather customer feedback on new descriptions'
        ],
        abTestRecommendations: [
          'Test emotional vs. rational appeals',
          'Compare different call-to-action approaches',
          'Evaluate impact of technical details inclusion',
          'Measure title length optimization effects'
        ],
      };
    }

    try {
      let products;

      if (productSku) {
        // Get specific product by searching through all products
        const { items } = await getUnifiedInventoryFromDB(companyId, { limit: 100 });
        products = items.filter(item => item.sku === productSku);
      } else {
        // Get multiple products for batch optimization
        const { items } = await getUnifiedInventoryFromDB(companyId, { 
          limit: 10,
          sortBy: 'inventory_quantity',
          sortDirection: 'desc'
        });
        products = items;
      }

      if (!products || products.length === 0) {
        throw new Error('No products found for description optimization');
      }

      // Transform products for AI analysis
      const productData = products.map(product => ({
        sku: product.sku,
        title: product.product_title || product.title || 'Untitled Product',
        description: (product.body_html || product.description || '') as string,
        price: (product.price || 0) / 100, // Convert cents to dollars
        category: product.product_type || null,
      }));

      const { output } = await dynamicDescriptionPrompt({
        products: productData,
        optimizationType,
        targetAudience,
        tone,
        includeKeywords,
        maxLength,
      }, { model: config.ai.model });

      if (!output) {
        throw new Error("AI failed to generate optimized descriptions.");
      }

      return output;
    } catch (e) {
      logError(e, { 
        context: `[Dynamic Description Flow] Failed for company ${companyId}, optimization: ${optimizationType}` 
      });
      throw new Error("An error occurred while generating optimized product descriptions.");
    }
  }
);

// Define a tool that wraps the flow
export const getDynamicDescriptions = ai.defineTool(
  {
    name: 'getDynamicDescriptions',
    description: "Generates AI-optimized product descriptions for better conversions and SEO. Use this for improving product copy, SEO optimization, or audience-specific content creation.",
    inputSchema: DynamicDescriptionInputSchema,
    outputSchema: DynamicDescriptionOutputSchema
  },
  async (input) => dynamicDescriptionFlow(input)
);
