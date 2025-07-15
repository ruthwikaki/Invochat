'use server';
/**
 * @fileOverview A Genkit flow to automatically map CSV columns to database fields.
 */

import { ai } from '@/ai/genkit';
import { CsvMappingInputSchema, CsvMappingOutputSchema, type CsvMappingInput, type CsvMappingOutput } from '@/types';

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
  // Sanitize headers before passing to AI to prevent prompt injection with malicious characters.
  const sanitizedInput: CsvMappingInput = {
    ...input,
    csvHeaders: input.csvHeaders.map(h => 
      h.replace(/[^\w\s-]/g, '').substring(0, 100)
    ),
  };
  
  const { output } = await csvMappingPrompt(sanitizedInput);
  if (!output) {
    return {
      mappings: [],
      unmappedColumns: input.csvHeaders,
    };
  }
  return output;
}

