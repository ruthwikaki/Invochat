
import { logger } from './logger'

export function isError(value: unknown): value is Error {
  return value instanceof Error
}

export function getErrorMessage(error: unknown): string {
  if (isError(error)) {
    return error.message
  }
  if (typeof error === 'string') {
    return error
  }
  if (error && typeof error === 'object') {
    if ('message' in error && typeof error.message === 'string') {
      return error.message;
    }
    try {
      return JSON.stringify(error);
    } catch {
      // Fallback if stringification fails
    }
  }
  return 'An unknown error occurred'
}

export function logError(error: unknown, context?: Record<string, any>): void {
  const message = getErrorMessage(error)
  const logMessage = context ? `${JSON.stringify(context)}: ${message}` : message
  
  if (isError(error)) {
    logger.error(logMessage, { error, stack: error.stack, ...context })
  } else {
    logger.error(logMessage, { error, ...context })
  }
}

export class AppError extends Error {
  constructor(
    message: string,
    public code: string,
    public statusCode: number = 500
  ) {
    super(message)
    this.name = 'AppError'
  }
}

export function handleAsyncError<T extends (...args: any[]) => Promise<any>>(
  fn: T
): T {
  return ((...args: any[]) => {
    return fn(...args).catch((error: unknown) => {
      logError(error, { functionName: fn.name })
      throw error
    })
  }) as T
}
