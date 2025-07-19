'use server';
/**
 * @fileOverview A Genkit flow to generate product descriptions.
 */

import { ai } from '@/ai/genkit';
import { z } from 'zod';

const GenerateDescriptionInputSchema = z.object({
  productName: z.string(),
  category: z.string().optional(),
  keywords: z.array(z.string()),
});

const GenerateDescriptionOutputSchema = z.object({
  suggestedName: z.string().describe("A catchy, SEO-friendly product name."),
  description: z.string().describe("A compelling, paragraph-long product description focusing on benefits."),
});

export const generateDescriptionPrompt = ai.definePrompt({
  name: 'generateDescriptionPrompt',
  input: { schema: GenerateDescriptionInputSchema },
  output: { schema: GenerateDescriptionOutputSchema },
  prompt: `
    You are an expert e-commerce copywriter. Your task is to generate a compelling name and description for a product.

    **Product Information:**
    - Current Name: {{{productName}}}
    - Category: {{{category}}}
    - Keywords: {{{json keywords}}}

    **Your Task:**
    1.  **Create a Suggested Name:** Generate a new, catchy, and SEO-friendly name for the product.
    2.  **Write a Description:** Write a single, compelling paragraph for the product description. Focus on the benefits for the customer, not just the features. Use the provided keywords naturally. The tone should be persuasive and professional.

    Provide your response in the specified JSON format.
  `,
});

export const generateProductDescription = ai.defineTool({
    name: 'generateProductDescription',
    description: "Generates a new product name and description based on keywords.",
    inputSchema: GenerateDescriptionInputSchema,
    outputSchema: GenerateDescriptionOutputSchema,
}, async (input) => {
    const { output } = await generateDescriptionPrompt(input);
    if (!output) {
        throw new Error("AI failed to generate a product description.");
    }
    return output;
});
