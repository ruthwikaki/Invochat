
/**
 * @fileoverview A simple, centralized logger for the application.
 * This logger standardizes log output with timestamps and severity levels.
 */

type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

// Note: We avoid exporting a complex object directly to stay compatible with
// Next.js server-side module constraints. Each function is exported individually.
const log = (level: LogLevel, message: string, ...optionalParams: any[]) => {
  const timestamp = new Date().toISOString();
  console.log(`${timestamp} [${level}] - ${message}`, ...optionalParams);
};

function debug(message: string, ...optionalParams: any[]) {
    log('DEBUG', message, ...optionalParams);
}

function info(message: string, ...optionalParams: any[]) {
    log('INFO', message, ...optionalParams);
}

function warn(message: string, ...optionalParams: any[]) {
    log('WARN', message, ...optionalParams);
}

function error(message: string, ...optionalParams: any[]) {
    log('ERROR', message, ...optionalParams);
}

export const logger = {
  debug,
  info,
  warn,
  error,
};
