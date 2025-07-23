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
      // Attempt to stringify, but catch potential circular reference errors
      return JSON.stringify(error);
    } catch {
      // Fallback for non-stringifiable objects
      return 'An unknown and non-stringifiable object error occurred.';
    }
  }
  return 'An unknown and non-stringifiable error occurred.'
}


export function logError(error: unknown, context?: Record<string, any>): void {
  const message = getErrorMessage(error)
  
  if (isError(error)) {
    logger.error(message, { error, stack: error.stack, ...context })
  } else {
    logger.error(message, { error, ...context })
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
