/**
 * @fileoverview SMB-specific safety configurations.
 * This file centralizes all the guardrail settings that make the application
 * safe for small and medium-sized businesses.
 */

export const SMB_CONFIG = {
  operational: {
    // The maximum number of conversation history items to send to the AI.
    // Prevents excessive token usage and high API costs.
    maxConversationHistory: 50,
    
    // The maximum size for a single cached item in Redis (in bytes).
    // Prevents a single large query result from bloating the cache.
    maxCacheEntrySizeBytes: 1024 * 1024, // 1MB
    
    // Default time-to-live for cached items in minutes.
    // Ensures data stays relatively fresh for SMBs.
    defaultCacheExpiryMinutes: 15,
  },
  
  safety: {
    // Enables/disables the AI Decision Validator.
    enableAIDecisionValidation: true,
    
    // AI suggestions with confidence below this threshold will be flagged.
    aiConfidenceWarningThreshold: 0.7,
  }
};
