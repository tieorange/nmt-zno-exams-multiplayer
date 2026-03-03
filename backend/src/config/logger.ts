import pino from 'pino';

export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  // Adds service field to every log line — makes BE logs instantly identifiable when
  // copy-pasting a mixed log stream to an AI agent.
  base: { service: 'backend' },
  // Standard pino error serializer so Error objects in structured log calls
  // (e.g. logger.error({ error: err })) are serialized as { name, message, stack }.
  serializers: {
    err: pino.stdSerializers.err,
    error: pino.stdSerializers.err,
  },
  transport: process.env.NODE_ENV !== 'production'
    ? {
        target: 'pino-pretty',
        options: { colorize: true, translateTime: 'SYS:standard', ignore: 'pid,hostname' },
      }
    : undefined,
});
