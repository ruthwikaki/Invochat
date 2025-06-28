
import { z } from 'zod';

// Input schema for the universal chat flow
export const UniversalChatInputSchema = z.object({
  companyId: z.string(),
  conversationHistory: z.array(z.object({
    role: z.enum(['user', 'assistant', 'system']),
    content: z.string(),
  })),
});
export type UniversalChatInput = z.infer<typeof UniversalChatInputSchema>;

// Output schema for the universal chat flow
export const UniversalChatOutputSchema = z.object({
  response: z.string().describe("The natural language response to the user."),
  data: z.array(z.any()).optional().nullable().describe("The raw data retrieved from the database, if any, for visualizations."),
  visualization: z.object({
    type: z.enum(['table', 'bar', 'pie', 'line', 'treemap', 'scatter', 'none']),
    title: z.string().optional(),
    config: z.any().optional()
  }).optional().describe("A suggested visualization for the data."),
  confidence: z.number().min(0).max(1).describe("A score from 0.0 (low) to 1.0 (high) indicating the AI's confidence in the generated SQL query and response."),
  assumptions: z.array(z.string()).optional().describe("A list of any assumptions the AI had to make to answer the query."),
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;
