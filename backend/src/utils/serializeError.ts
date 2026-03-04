export interface SerializedError {
  name: string;
  message: string;
  stack?: string;
  cause?: unknown;
}

/**
 * Safely serializes any thrown value into a stable object shape.
 * Handles Error instances, plain objects, strings, and nested causes.
 * Never throws — safe to call inside logger handlers.
 */
export function serializeError(err: unknown): SerializedError {
  if (err instanceof Error) {
    return {
      name: err.name,
      message: err.message,
      stack: err.stack,
      cause: err.cause !== undefined ? serializeError(err.cause) : undefined,
    };
  }
  if (typeof err === 'object' && err !== null) {
    try {
      return { name: 'UnknownError', message: JSON.stringify(err) };
    } catch {
      return { name: 'UnknownError', message: '[circular or unserializable object]' };
    }
  }
  return { name: 'UnknownError', message: String(err) };
}
