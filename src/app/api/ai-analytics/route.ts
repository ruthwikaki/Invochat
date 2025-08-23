import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { 
  suggestBundlesFlow,
  economicImpactFlow,
  dynamicDescriptionFlow
} from '@/ai/flows';

/**
 * Advanced AI Analytics API Route
 * Provides comprehensive AI-powered business intelligence and recommendations
 */
export async function GET(request: NextRequest) {
  try {
    const { user: authUser } = await requireUser(request);
    const companyId = authUser.user_metadata?.company_id;
    
    if (!companyId) {
      return NextResponse.json(
        { error: 'Company ID not found in user metadata' },
        { status: 400 }
      );
    }
    
    const { searchParams } = new URL(request.url);
    const analysisType = searchParams.get('type');
    const format = searchParams.get('format') || 'json';
    
    if (!analysisType) {
      return NextResponse.json(
        { error: 'Analysis type is required. Available types: bundle-suggestions, economic-impact, dynamic-descriptions' },
        { status: 400 }
      );
    }

    let result;

    switch (analysisType) {
      case 'bundle-suggestions':
        const bundleCount = parseInt(searchParams.get('count') || '5');
        result = await suggestBundlesFlow({
          companyId,
          count: bundleCount
        });
        break;

      case 'economic-impact':
        const scenarioType = searchParams.get('scenario') as any;
        const priceChange = searchParams.get('priceChange');
        const inventoryReduction = searchParams.get('inventoryReduction');
        
        if (!scenarioType) {
          return NextResponse.json(
            { error: 'Scenario type is required for economic impact analysis' },
            { status: 400 }
          );
        }

        result = await economicImpactFlow({
          companyId,
          scenarioType,
          parameters: {
            priceChangePercent: priceChange ? parseFloat(priceChange) : undefined,
            inventoryReductionPercent: inventoryReduction ? parseFloat(inventoryReduction) : undefined,
          }
        });
        break;

      case 'dynamic-descriptions':
        const productSku = searchParams.get('sku') || undefined;
        const optimizationType = (searchParams.get('optimization') as any) || 'conversion';
        const targetAudience = (searchParams.get('audience') as any) || 'general';
        const tone = (searchParams.get('tone') as any) || 'professional';
        const maxLength = parseInt(searchParams.get('maxLength') || '300');
        
        result = await dynamicDescriptionFlow({
          companyId,
          productSku,
          optimizationType,
          targetAudience,
          tone,
          maxLength
        });
        break;

      default:
        return NextResponse.json(
          { error: `Unknown analysis type: ${analysisType}` },
          { status: 400 }
        );
    }

    // Format response based on requested format
    if (format === 'summary') {
      // Return a simplified summary for dashboard widgets
      const summary = {
        type: analysisType,
        timestamp: new Date().toISOString(),
        companyId,
        ...(analysisType === 'bundle-suggestions' && {
          bundleCount: (result as any)?.suggestions?.length || 0,
          totalPotentialRevenue: (result as any)?.totalPotentialRevenue || 0,
          topBundle: (result as any)?.suggestions?.[0]?.bundleName || 'None'
        }),
        ...(analysisType === 'economic-impact' && {
          revenueImpact: (result as any)?.analysis?.revenueImpact?.revenueChangePercent || 0,
          profitImpact: (result as any)?.analysis?.profitabilityImpact?.profitChangePercent || 0,
          riskLevel: (result as any)?.analysis?.riskAssessment?.riskLevel || 'medium'
        }),
        ...(analysisType === 'dynamic-descriptions' && {
          productsOptimized: (result as any)?.optimizedProducts?.length || 0,
          avgImprovementScore: (result as any)?.optimizedProducts?.reduce((sum: number, p: any) => sum + p.improvementScore, 0) / ((result as any)?.optimizedProducts?.length || 1) || 0,
          conversionImprovement: (result as any)?.performanceProjections?.estimatedConversionImprovement || 0
        })
      };
      return NextResponse.json(summary);
    }

    return NextResponse.json({
      success: true,
      data: result,
      metadata: {
        analysisType,
        timestamp: new Date().toISOString(),
        companyId,
        userId: authUser.id
      }
    });

  } catch (error) {
    console.error('[AI Analytics API] Error:', error);
    
    if (error instanceof Error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500 }
      );
    }

    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const { user: authUser } = await requireUser(request);
    const companyId = authUser.user_metadata?.company_id;
    
    if (!companyId) {
      return NextResponse.json(
        { error: 'Company ID not found in user metadata' },
        { status: 400 }
      );
    }
    
    const body = await request.json();
    const { analysisType, parameters = {} } = body;
    
    if (!analysisType) {
      return NextResponse.json(
        { error: 'Analysis type is required in request body' },
        { status: 400 }
      );
    }

    let result;

    switch (analysisType) {
      case 'bundle-suggestions':
        result = await suggestBundlesFlow({
          companyId,
          count: parameters.count || 5
        });
        break;

      case 'economic-impact':
        if (!parameters.scenarioType) {
          return NextResponse.json(
            { error: 'Scenario type is required for economic impact analysis' },
            { status: 400 }
          );
        }

        result = await economicImpactFlow({
          companyId,
          scenarioType: parameters.scenarioType,
          parameters: {
            priceChangePercent: parameters.priceChangePercent,
            inventoryReductionPercent: parameters.inventoryReductionPercent,
            newProductCount: parameters.newProductCount,
            marketExpansionPercent: parameters.marketExpansionPercent,
            costReductionPercent: parameters.costReductionPercent,
          }
        });
        break;

      case 'dynamic-descriptions':
        result = await dynamicDescriptionFlow({
          companyId,
          productSku: parameters.productSku,
          optimizationType: parameters.optimizationType || 'conversion',
          targetAudience: parameters.targetAudience || 'general',
          tone: parameters.tone || 'professional',
          includeKeywords: parameters.includeKeywords || [],
          maxLength: parameters.maxLength || 300
        });
        break;

      case 'batch-analysis':
        // Run multiple analyses for comprehensive insights
        const [bundleResults, economicResults] = await Promise.all([
          suggestBundlesFlow({
            companyId,
            count: parameters.bundleCount || 3
          }),
          economicImpactFlow({
            companyId,
            scenarioType: parameters.economicScenario || 'pricing_optimization',
            parameters: parameters.economicParameters || {}
          })
        ]);

        result = {
          bundleAnalysis: bundleResults,
          economicAnalysis: economicResults,
          combinedInsights: {
            totalRevenueOpportunity: ((bundleResults as any)?.totalPotentialRevenue || 0) + 
                                   ((economicResults as any)?.analysis?.revenueImpact?.revenueChange || 0),
            strategicRecommendations: [
              ...((bundleResults as any)?.implementationRecommendations || []),
              ...((economicResults as any)?.analysis?.recommendations || [])
            ],
            riskAssessment: (economicResults as any)?.analysis?.riskAssessment || null
          }
        };
        break;

      default:
        return NextResponse.json(
          { error: `Unknown analysis type: ${analysisType}` },
          { status: 400 }
        );
    }

    return NextResponse.json({
      success: true,
      data: result,
      metadata: {
        analysisType,
        timestamp: new Date().toISOString(),
        companyId,
        userId: authUser.id,
        parameters
      }
    });

  } catch (error) {
    console.error('[AI Analytics API] POST Error:', error);
    
    if (error instanceof Error) {
      return NextResponse.json(
        { error: error.message },
        { status: 500 }
      );
    }

    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    );
  }
}
