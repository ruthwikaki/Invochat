

/**
 * @fileoverview A simple, centralized logger for the application.
 * This logger standardizes log output with timestamps and severity levels.
 * It's designed to be a lightweight starting point that can easily be
 * replaced by a more advanced library like Winston or Pino in the future
 * without needing to refactor the entire application.
 */

type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

const log = (level: LogLevel, message: string, ...optionalParams: any[]) => {
  const timestamp = new Date().toISOString();
  // In a real production system, you might add a request ID or user context here.
  // The output is structured for easier parsing by log management systems.
  console.log(`${timestamp} [${level}] - ${message}`, ...optionalParams);
};

export const logger = {
  debug: (message: string, ...optionalParams: any[]) => log('DEBUG', message, ...optionalParams),
  info: (message: string, ...optionalParams: any[]) => log('INFO', message, ...optionalParams),
  warn: (message: string, ...optionalParams: any[]) => log('WARN', message, ...optionalParams),
  error: (message: string, ...optionalParams: any[]) => log('ERROR', message, ...optionalParams),
};
