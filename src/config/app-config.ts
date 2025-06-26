/**
 * @fileoverview Centralized configuration for the InvoChat application.
 *
 * This file consolidates hardcoded values into a single, easily manageable object.
 * It helps in avoiding magic numbers and strings scattered across the codebase,
 * making the application more maintainable and configurable.
 */
export const APP_CONFIG = {
  ai: {
    model: process.env.AI_MODEL || 'gemini-1.5-pro',
    maxRetries: 2,
    historyLimit: 10,
  },
  database: {
    queryLimit: 1000,
  },
  businessLogic: {
    deadStockDays: 90,
  },
  chat: {
    quickActions: [
      "What's not selling?",
      'Show supplier performance',
      'Create inventory chart',
      'What needs reordering?',
    ],
  },
};
