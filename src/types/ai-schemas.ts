
import { z } from 'zod';

// A single part of a multi-modal message
const ContentPartSchema = z.object({
    text: z.string(),
    // We only support text for now, but this structure allows for future expansion
    // to include images, tool calls, etc.
});

// A message in the conversation history
const HistoryMessageSchema = z.object({
  role: z.enum(['user', 'assistant']),
  content: z.array(ContentPartSchema),
});

// Input schema for the universal chat flow
export const UniversalChatInputSchema = z.object({
  companyId: z.string().uuid(),
  conversationHistory: z.array(HistoryMessageSchema),
});
export type UniversalChatInput = z.infer<typeof UniversalChatInputSchema>;


// Output schema for the universal chat flow
export const UniversalChatOutputSchema = z.object({
  response: z.string().describe("The natural language response to the user."),
  data: z.array(z.record(z.string(), z.unknown())).optional().nullable().describe("The raw data retrieved from the database, if any, for visualizations."),
  visualization: z.object({
    type: z.enum(['table', 'bar', 'pie', 'line', 'treemap', 'scatter', 'none']),
    title: z.string().optional(),
    config: z.record(z.string(), z.unknown()).optional()
  }).optional().describe("A suggested visualization for the data."),
  confidence: z.number().min(0).max(1).describe("A score from 0.0 (low) to 1.0 (high) indicating the AI's confidence in the generated SQL query and response."),
  assumptions: z.array(z.string()).optional().describe("A list of any assumptions the AI had to make to answer the query."),
  // Add a field to specify which tool was called, if any.
  toolName: z.string().optional().describe("The name of the tool that was called, if any."),
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;
