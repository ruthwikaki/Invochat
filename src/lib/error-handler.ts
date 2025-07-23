
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
  return 'An unknown error occurred'
}

export function logError(error: unknown, context?: string): void {
  const message = getErrorMessage(error)
  const logMessage = context ? `[${context}] ${message}` : message
  
  if (isError(error)) {
    logger.error(logMessage, { error, stack: error.stack })
  } else {
    logger.error(logMessage, { error })
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
      logError(error, fn.name)
      throw error
    })
  }) as T
}
