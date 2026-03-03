import 'dotenv/config';
import './config/supabase.js';  // validates env vars + initializes client on import
import express, { Request, Response, NextFunction } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { logger } from './config/logger.js';
import routes from './presentation/routes/index.js';

process.on('unhandledRejection', (reason) => {
    logger.error(`[Unhandled Rejection] ${reason}`);
    process.exit(1);
});

process.on('uncaughtException', (err) => {
    logger.error(`[Uncaught Exception] ${err}`);
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
app.use('/api', routes);

// Global error middleware — must have 4 parameters so Express recognises it as an error handler.
// Returns a stable { error, code? } JSON shape for all /api/* failures.
// eslint-disable-next-line @typescript-eslint/no-unused-vars
app.use('/api', (err: unknown, _req: Request, res: Response, _next: NextFunction) => {
    const message = err instanceof Error ? err.message : String(err);
    logger.error(`[ErrorMiddleware] Unhandled route error | ${message}`);
    // Don't leak stack traces to the client in production
    res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => logger.info(`[Server] Listening on port ${PORT}`));
