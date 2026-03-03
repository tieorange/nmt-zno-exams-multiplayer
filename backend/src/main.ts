import 'dotenv/config';
import './config/supabase.js';  // validates env vars + initializes client on import
import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { logger } from './config/logger.js';
import { serializeError } from './utils/serializeError.js';
import { requestIdMiddleware } from './middleware/requestId.js';
import { requestLoggerMiddleware } from './middleware/requestLogger.js';
import routes from './presentation/routes/index.js';

process.on('unhandledRejection', (reason) => {
    logger.error({ event: 'process.unhandledRejection', error: serializeError(reason) });
    process.exit(1);
});

process.on('uncaughtException', (err) => {
    logger.error({ event: 'process.uncaughtException', error: serializeError(err) });
    process.exit(1);
});

const app = express();

// CORS configuration - require explicit origin in production
const isProduction = process.env.NODE_ENV === 'production';
const corsOrigin = process.env.CORS_ORIGIN;

// Development defaults (only if CORS_ORIGIN is not set).
// Port 5000 is the pinned Flutter web port used by `make frontend`.
const developmentOrigins = ['http://localhost:3000', 'http://localhost:4200', 'http://localhost:5000'];

let allowedOrigin: string | string[];

if (corsOrigin) {
    // If explicitly configured, use it
    allowedOrigin = corsOrigin;
} else if (isProduction) {
    // In production, CORS_ORIGIN must be explicitly set
    throw new Error(
        'CORS_ORIGIN environment variable is required in production. ' +
        'Please set CORS_ORIGIN to your frontend URL (e.g., https://your-app.vercel.app)'
    );
} else {
    // In development, allow common localhost ports
    allowedOrigin = developmentOrigins;
}

app.use(cors({ origin: allowedOrigin }));
app.use(helmet());
app.use(express.json());
// Attach requestId first so all subsequent logs can reference it
app.use(requestIdMiddleware);
app.use(requestLoggerMiddleware);
app.use('/api', routes);

// Global error middleware — must have 4 parameters so Express recognises it as an error handler.
// Returns a stable { error } JSON shape for all /api/* failures.
// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use('/api', (err: unknown, req: Request, res: Response, _next: NextFunction) => {
    const requestId = res.locals['requestId'] as string | undefined;
    logger.error({
        event: 'http.error.unhandled',
        requestId,
        method: req.method,
        path: req.path,
        error: serializeError(err),
    });
    // Don't leak stack traces to the client in production
    res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => logger.info({ event: 'server.start', port: PORT }));
