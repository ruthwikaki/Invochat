
/**
 * @fileoverview A simple, centralized logger for the application.
 * This logger standardizes log output with timestamps and severity levels.
 * In production, it outputs structured JSON for better interoperability with logging services.
 */

type LogLevel = 'DEBUG' | 'INFO' | 'WARN' | 'ERROR';

const isProduction = process.env.NODE_ENV === 'production';

// Note: We avoid exporting a complex object directly to stay compatible with
// Next.js server-side module constraints. Each function is exported individually.
const log = (level: LogLevel, message: string, ...optionalParams: any[]) => {
  // In production, only log INFO and above unless a specific flag is set.
  if (isProduction && (level === 'DEBUG')) {
      return;
  }
  
  const timestamp = new Date().toISOString();
  
  if (isProduction) {
    const logObject = {
      timestamp,
      level,
      message,
      ...optionalParams[0] && typeof optionalParams[0] === 'object' ? optionalParams[0] : { details: optionalParams },
    };
    console.log(JSON.stringify(logObject));
  } else {
    console.log(`${timestamp} [${level}] - ${message}`, ...optionalParams);
  }
};

function debug(message: string, ...optionalParams: any[]) {
    // To reduce noise, only log DEBUG level messages in non-production environments.
    if (!isProduction) {
        log('DEBUG', message, ...optionalParams);
    }
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
