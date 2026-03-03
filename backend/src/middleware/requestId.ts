import { Request, Response, NextFunction } from 'express';
import { v4 as uuid } from 'uuid';

/**
 * Attaches a request ID to every incoming request.
 * Forwards the existing x-request-id header if present, otherwise generates a new UUID.
 * The ID is stored in res.locals.requestId and echoed back in the response header.
 */
export function requestIdMiddleware(req: Request, res: Response, next: NextFunction): void {
  const id = (req.headers['x-request-id'] as string | undefined) || uuid();
  res.locals['requestId'] = id;
  res.setHeader('x-request-id', id);
  next();
}
