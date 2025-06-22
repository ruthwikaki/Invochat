'use server';

/**
 * @fileOverview A Genkit flow for dynamically generating chart configurations
 * based on natural language user queries about their inventory data.
 */

import { ai } from '@/ai/genkit';
import { getDataForChart } from '@/services/database';
import { z } from 'zod';

// Define the input schema for the chart generation flow.
const GenerateChartInputSchema = z.object({
  query: z.string().describe('The user query asking for a data visualization.'),
});
export type GenerateChartInput = z.infer<typeof GenerateChartInputSchema>;

// Define the output schema for the chart generation flow.
// This is a structured JSON object that the frontend can use to render a chart.
const GenerateChartOutputSchema = z.object({
  chartType: z.enum(['bar', 'pie', 'line']).describe('The type of chart to render.'),
  title: z.string().describe('A descriptive title for the chart.'),
  data: z.array(z.any()).describe('The data array for the chart.'),
  config: z.object({
      dataKey: z.string().describe('The key in the data objects that holds the numerical value.'),
      nameKey: z.string().optional().describe('The key in the data objects for the category name or label.'),
      xAxisKey: z.string().optional().describe('The key for the X-axis labels in bar or line charts.'),
  }).describe('Configuration for rendering the chart.'),
});
export type GenerateChartOutput = z.infer<typeof GenerateChartOutputSchema>;

// Define a Genkit tool that allows the AI to fetch data.
const fetchDataTool = ai.defineTool(
  {
    name: 'getDataForChart',
    description: 'Fetches data from the database based on a user query. Use this to get data for visualizations. Examples: "slowest moving inventory", "warehouse distribution", "sales velocity by category", "inventory aging", "supplier performance", "inventory value by category"',
    inputSchema: z.object({ query: z.string() }),
    outputSchema: z.array(z.any()),
  },
  async ({ query }) => {
    return getDataForChart(query);
  }
);

// Define the main prompt for the chart generation flow.
const chartPrompt = ai.definePrompt({
  name: 'chartPrompt',
  input: { schema: GenerateChartInputSchema },
  output: { schema: GenerateChartOutputSchema },
  tools: [fetchDataTool],
  prompt: `You are an expert data visualization assistant for an inventory management system.
  Your goal is to turn a user's question into a valid chart configuration object.

  1.  Analyze the user's query: {{{query}}}
  2.  Determine the best chart type (bar, pie, or line) to represent the data. If the user specifies a chart type, use that.
        - Use 'pie' for distributions or proportions (e.g., "warehouse distribution").
        - Use 'bar' for comparisons between categories (e.g., "sales velocity", "dead stock value").
        - Use 'line' for trends over time (though not supported by the current tool).
  3.  Formulate a query for the \`getDataForChart\` tool based on the user's request.
  4.  Call the \`getDataForChart\` tool to get the data.
  5.  From the tool's output, construct a complete JSON object matching the \`GenerateChartOutputSchema\`.
        - The 'data' field should be the direct output from the tool.
        - Create a descriptive 'title' for the chart.
        - In 'config', correctly identify the 'dataKey' (the numeric value) and 'nameKey'/'xAxisKey' (the label) from the data objects returned by the tool. For most charts, 'name' is the name/x-axis key and 'value' is the data key.
  
  Example tool output: \`[{ name: 'Category A', value: 100 }, { name: 'Category B', value: 200 }]\`
  - For this data, \`nameKey\` or \`xAxisKey\` should be 'name' and \`dataKey\` should be 'value'.
  `,
});

// Define the Genkit flow for chart generation.
const generateChartFlow = ai.defineFlow(
  {
    name: 'generateChartFlow',
    inputSchema: GenerateChartInputSchema,
    outputSchema: GenerateChartOutputSchema,
  },
  async (input) => {
    const { output } = await chartPrompt(input);
    if (!output) {
      throw new Error('Could not generate chart configuration.');
    }
    return output;
  }
);

// Exported function to be called by server actions.
export async function generateChart(input: GenerateChartInput): Promise<GenerateChartOutput> {
  return generateChartFlow(input);
}
