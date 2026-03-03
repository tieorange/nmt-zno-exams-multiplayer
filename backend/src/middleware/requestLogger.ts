import { Request, Response, NextFunction } from 'express';
import { logger } from '../config/logger.js';

/**
 * Logs every HTTP request start and finish with timing, status code, and outcome.
 * Pairs start/finish via requestId set by requestIdMiddleware.
 * Body is intentionally omitted to avoid logging sensitive data.
 */
export function requestLoggerMiddleware(req: Request, res: Response, next: NextFunction): void {
  const start = Date.now();
  const requestId = res.locals['requestId'] as string;

  logger.info({
    event: 'http.request.start',
    requestId,
    method: req.method,
    path: req.path,
    query: Object.keys(req.query).length > 0 ? req.query : undefined,
  });

  res.on('finish', () => {
    const durationMs = Date.now() - start;
    logger.info({
      event: 'http.request.finish',
      requestId,
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      durationMs,
      outcome: res.statusCode < 400 ? 'success' : 'failure',
    });
  });

  next();
}
