import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { enhancedForecastingService } from '@/services/enhanced-demand-forecasting';
import { logError } from '@/lib/error-handler';

export async function GET(request: NextRequest) {
  try {
    const { user } = await requireUser(request);
    const { searchParams } = new URL(request.url);
    const sku = searchParams.get('sku');
    const forecastDays = parseInt(searchParams.get('forecastDays') || '90');

    if (!sku) {
      return NextResponse.json(
        { error: 'SKU parameter is required' },
        { status: 400 }
      );
    }

    const forecast = await enhancedForecastingService.generateEnhancedForecast(
      user.id, // Use user.id as company identifier
      sku,
      forecastDays
    );

    if (!forecast) {
      return NextResponse.json(
        { error: 'Unable to generate forecast - insufficient data' },
        { status: 404 }
      );
    }

    return NextResponse.json({
      success: true,
      data: forecast
    });

  } catch (error: any) {
    logError(error, { context: 'Enhanced demand forecast API error' });
    return NextResponse.json(
      { error: 'Failed to generate enhanced forecast', details: error.message },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const { user } = await requireUser(request);
    const body = await request.json();
    const { skus, forecastDays = 90 } = body;

    if (!Array.isArray(skus) || skus.length === 0) {
      return NextResponse.json(
        { error: 'SKUs array is required' },
        { status: 400 }
      );
    }

    const forecasts = await Promise.all(
      skus.map(async (sku: string) => {
        try {
          return await enhancedForecastingService.generateEnhancedForecast(
            user.id, // Use user.id as company identifier
            sku,
            forecastDays
          );
        } catch (error) {
          logError(error, { context: 'Bulk forecast generation failed', sku });
          return null;
        }
      })
    );

    const validForecasts = forecasts.filter(f => f !== null);

    return NextResponse.json({
      success: true,
      data: {
        forecasts: validForecasts,
        requested: skus.length,
        generated: validForecasts.length
      }
    });

  } catch (error: any) {
    logError(error, { context: 'Bulk enhanced demand forecast API error' });
    return NextResponse.json(
      { error: 'Failed to generate bulk forecasts', details: error.message },
      { status: 500 }
    );
  }
}
