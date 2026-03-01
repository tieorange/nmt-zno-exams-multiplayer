import 'dotenv/config';
import './config/supabase.js';  // validates env vars + initializes client on import
import express from 'express';
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

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(helmet());
app.use(express.json());
app.use('/api', routes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => logger.info(`[Server] Listening on port ${PORT}`));
