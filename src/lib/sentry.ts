
/**
 * @fileoverview This file is intentionally left blank. 
 * Sentry is now initialized via its own configuration files (sentry.*.config.ts)
 * as per the official Next.js integration guide. This approach ensures Sentry
 * is loaded correctly in all Next.js runtimes (client, server, edge).
 * This file is kept to prevent breaking any legacy imports but should not be used.
 */
import { logger } from './logger';

logger.info('[Sentry] SDK now initialized via dedicated config files.');

