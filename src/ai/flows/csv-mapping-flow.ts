'use server';
/**
 * @fileOverview A Genkit flow to automatically map CSV columns to database fields.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';

const CsvMappingInputSchema = z.object({
  csvHeaders: z.array(z.string()).describe("The list of column headers from the user's CSV file."),
  sampleRows: z.array(z.record(z.string())).describe("An array of sample rows (as objects) from the CSV to provide data context."),
  expectedDbFields: z.array(z.string()).describe("The list of target database fields we need to map to."),
});
export type CsvMappingInput = z.infer<typeof CsvMappingInputSchema>;

export const CsvMappingOutputSchema = z.object({
  mappings: z.array(z.object({
    csvColumn: z.string().describe("The original column header from the CSV."),
    dbField: z.string().describe("The database field it maps to."),
    confidence: z.number().min(0).max(1).describe("The AI's confidence in this specific mapping."),
  })),
  unmappedColumns: z.array(z.string()).describe("A list of CSV columns that could not be confidently mapped."),
});
export type CsvMappingOutput = z.infer<typeof CsvMappingOutputSchema>;

const csvMappingPrompt = ai.definePrompt({
  name: 'csvMappingPrompt',
  input: { schema: CsvMappingInputSchema },
  output: { schema: CsvMappingOutputSchema },
  prompt: `
    You are an intelligent data mapping assistant. Your task is to map the columns from a user-uploaded CSV file to the expected database fields. You must be able to handle variations in naming, casing, and language (especially English, Spanish, and French).

    **Expected Database Fields:**
    {{#each expectedDbFields}}
    - {{{this}}}
    {{/each}}

    **User's CSV Headers:**
    {{#each csvHeaders}}
    - {{{this}}}
    {{/each}}

    **Sample Data Rows (for context):**
    {{{json sampleRows}}}

    **Your Task:**
    1.  **Analyze:** For each CSV header, determine which database field it best corresponds to. Use the sample data to understand the content of each column.
        - "Product Code", "Item #", "SKU", "Código de Producto" should all map to 'sku'.
        - "Description", "Product Name", "Nombre del Producto" should all map to 'name'.
        - "Qty", "Quantity on Hand", "Stock", "Cantidad" should all map to 'quantity'.
    2.  **Confidence Score:** For each mapping, provide a confidence score from 0.0 (uncertain) to 1.0 (certain). A direct match like 'sku' -> 'sku' should be 1.0. A plausible match like "Item Description" -> 'name' might be 0.8.
    3.  **Unmapped Columns:** List any CSV headers that you cannot map to any of the expected database fields with at least 0.5 confidence.
    4.  **Output:** Return a single JSON object that strictly adheres to the output schema. Ensure every original CSV header is accounted for in either 'mappings' or 'unmappedColumns'.
  `,
});

export async function suggestCsvMappings(input: CsvMappingInput): Promise<CsvMappingOutput> {
  const { output } = await csvMappingPrompt(input);
  if (!output) {
    return {
      mappings: [],
      unmappedColumns: input.csvHeaders,
    };
  }
  return output;
}
