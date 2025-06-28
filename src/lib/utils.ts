import { clsx, type ClassValue } from "clsx"
import { twMerge } from "tailwind-merge"

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/**
 * A simple linear regression function.
 * @param data An array of objects with x and y properties.
 * @returns An object with the slope and y-intercept of the regression line.
 */
export function linearRegression(data: { x: number; y: number }[]): { slope: number; intercept: number } {
  const n = data.length;
  if (n < 2) return { slope: 0, intercept: data[0]?.y || 0 };
  
  let sumX = 0, sumY = 0, sumXY = 0, sumXX = 0;
  for (const point of data) {
    sumX += point.x;
    sumY += point.y;
    sumXY += point.x * point.y;
    sumXX += point.x * point.x;
  }
  
  const slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
  const intercept = (sumY - slope * sumX) / n;
  
  return { slope: isNaN(slope) ? 0 : slope, intercept: isNaN(intercept) ? sumY / n : intercept };
}


// Placeholder statistical functions for future implementation
export function calculateTrend(data: Array<{date: Date, value: number}>) {
  // A real implementation would perform linear regression over time.
  console.log("Trend calculation placeholder for:", data);
  return { slope: 0.1, intercept: 50 };
}

export function detectSeasonality(data: Array<{date: Date, value: number}>) {
  // A real implementation would use techniques like Fourier analysis or decomposition.
  console.log("Seasonality detection placeholder for:", data);
  return { isSeasonal: false, period: null };
}

export function forecastWithConfidence(
  historical: number[], 
  periods: number
): {forecast: number[], upper: number[], lower: number[]} {
  // A real implementation would use methods like ARIMA or Exponential Smoothing (ETS).
  console.log("Forecasting placeholder for:", historical, "for", periods, "periods");
  const lastValue = historical[historical.length - 1] || 0;
  const forecast = Array.from({ length: periods }, (_, i) => lastValue * (1 + 0.05 * (i + 1)));
  const upper = forecast.map(f => f * 1.2);
  const lower = forecast.map(f => f * 0.8);
  return { forecast, upper, lower };
}

export function detectAnomalies(data: number[], sensitivity: number = 2) {
  // A real implementation would use statistical methods like Z-score or Isolation Forests.
  const mean = data.reduce((a, b) => a + b, 0) / data.length;
  const stdDev = Math.sqrt(data.map(x => Math.pow(x - mean, 2)).reduce((a, b) => a + b, 0) / data.length);
  const threshold = stdDev * sensitivity;
  console.log("Anomaly detection placeholder for:", data);
  return data.map((value, index) => ({
    index,
    value,
    isAnomaly: Math.abs(value - mean) > threshold,
  })).filter(item => item.isAnomaly);
}
