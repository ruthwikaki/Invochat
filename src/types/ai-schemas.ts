

'use server';

import { z } from 'zod';

export const AnomalySchema = z.object({
  date: z.string(),
  anomaly_type: z.string(),
  daily_revenue: z.number(),
  avg_revenue: z.number(),
  deviation_percentage: z.number(),
});

// A single part of a multi-modal message, updated to support tool responses.
const ContentPartSchema = z.object({
  text: z.string().optional(),
  toolResponse: z.object({
    name: z.string(),
    output: z.any(),
  }).optional(),
});

// A message in the conversation history, aligned with Genkit's history message structure.
const HistoryMessageSchema = z.object({
  role: z.enum(['user', 'model']),
  content: z.array(z.object({text: z.string()})),
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
  data: z.any().optional().nullable().describe("The raw data retrieved from the database, if any. This could be an array of objects or a single object."),
  visualization: z.object({
    type: z.enum(['table', 'chart', 'alert', 'none']),
    data: z.array(z.record(z.string(), z.unknown())).describe("The data used for the visualization."),
    title: z.string().optional(),
    config: z.record(z.string(), z.unknown()).optional()
  }).optional().describe("A suggested visualization for the data."),
  confidence: z.number().min(0).max(1).describe("A score from 0.0 (low) to 1.0 (high) indicating the AI's confidence in the generated SQL query and response."),
  assumptions: z.array(z.string()).optional().describe("A list of any assumptions the AI had to make to answer the query."),
  isError: z.boolean().optional(),
  // Add a field to specify which tool was called, if any.
  toolName: z.string().optional().describe("The name of the tool that was called to generate this response, if applicable."),
});
export type UniversalChatOutput = z.infer<typeof UniversalChatOutputSchema>;

export const AnomalyExplanationInputSchema = z.object({
    type: z.string(),
    title: z.string(),
    message: z.string(),
    severity: z.string(),
    metadata: z.record(z.unknown()),
});
export type AnomalyExplanationInput = z.infer<typeof AnomalyExplanationInputSchema>;

export const AnomalyExplanationOutputSchema = z.object({
  explanation: z.string().describe("A concise, 1-2 sentence explanation for the anomaly or alert."),
  confidence: z.enum(['high', 'medium', 'low']).describe("The AI's confidence in its explanation."),
  suggestedAction: z.string().optional().describe("A brief, actionable suggestion for the user to take next."),
});
export type AnomalyExplanationOutput = z.infer<typeof AnomalyExplanationOutputSchema>;

export const HealthCheckResultSchema = z.object({
    healthy: z.boolean(),
    metric: z.number(),
    message: z.string(),
});
export type HealthCheckResult = z.infer<typeof HealthCheckResultSchema>;


    
