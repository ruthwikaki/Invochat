
/**
 * @fileoverview SMB-specific safety configurations.
 * This file centralizes all the guardrail settings that make the application
 * safe for small and medium-sized businesses.
 */

export const SMB_CONFIG = {
  financial: {
    // The maximum percentage of monthly revenue that a single PO can represent.
    // Prevents a single bad order from bankrupting the company.
    maxSingleOrderPercent: 0.15,
    
    // The maximum percentage of monthly revenue that can be tied up in all open POs.
    // Protects cash flow.
    maxTotalExposurePercent: 0.35,
    
    // The percentage of monthly revenue to always keep as a buffer.
    emergencyReservePercent: 0.10,

    // The maximum value for a PO that can be created without requiring manual review/approval.
    autoApprovalLimit: 100000, // $1,000.00 in cents
  },
  
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
    // Enables/disables all financial circuit breakers.
    enableFinancialCircuitBreakers: true,
    
    // Enables/disables the AI Decision Validator.
    enableAIDecisionValidation: true,
    
    // AI suggestions with confidence below this threshold will be flagged.
    aiConfidenceWarningThreshold: 0.7,
  }
};
