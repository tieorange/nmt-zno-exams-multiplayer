import 'dart:convert';
import 'package:logger/logger.dart';

/// Custom log printer that emits one structured JSON line per log call.
///
/// Supports two call styles:
///   1. Legacy string: logger.i('[Feature] event | key=value')
///      → parsed into { feature, event, context } automatically.
///   2. Structured map: logger.i({'feature': 'ApiService', 'event': 'api.request.finish', ...})
///      → merged directly into the output object.
///
/// Every emitted line always contains: ts, level, service.
/// When copying logs to an AI agent, just paste the relevant JSON lines —
/// all required context (feature, event, requestId, roomCode, etc.) is embedded.
class StructuredLogPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final ts = event.time.toIso8601String();
    final levelName = _levelName(event.level);

    final Map<String, dynamic> fields = {
      'ts': ts,
      'level': levelName,
      'service': 'frontend',
    };

    final msg = event.message;
    if (msg is Map) {
      // Structured call — merge all provided fields directly
      fields.addAll(Map<String, dynamic>.from(msg));
    } else {
      // Legacy string format: [Feature] event text | key1=val1 key2=val2
      final raw = msg.toString();
      final featureMatch = RegExp(r'^\[(\w+)\]\s*').firstMatch(raw);
      if (featureMatch != null) {
        fields['feature'] = featureMatch.group(1);
        final rest = raw.substring(featureMatch.end);
        final parts = rest.split(' | ');
        // Use the human label as event (spaces → underscores, lowercased)
        fields['event'] = parts[0].trim().replaceAll(' ', '_').toLowerCase();
        if (parts.length > 1) {
          final ctx = <String, dynamic>{};
          for (final kv in parts[1].split(' ')) {
            final eqIdx = kv.indexOf('=');
            if (eqIdx > 0) {
              ctx[kv.substring(0, eqIdx)] = kv.substring(eqIdx + 1);
            }
          }
          if (ctx.isNotEmpty) fields['context'] = ctx;
        }
      } else {
        fields['message'] = raw;
      }
    }

    if (event.error != null) {
      fields['error'] = event.error.toString();
    }
    if (event.stackTrace != null) {
      fields['stackTrace'] = event.stackTrace.toString();
    }

    try {
      return [jsonEncode(fields)];
    } catch (_) {
      // Fallback: emit a minimal safe line if encoding fails (e.g. circular objects)
      return ['{"ts":"$ts","level":"$levelName","service":"frontend","error":"log_encode_failed"}'];
    }
  }

  String _levelName(Level level) {
    switch (level) {
      case Level.trace:
        return 'TRACE';
      case Level.debug:
        return 'DEBUG';
      case Level.info:
        return 'INFO';
      case Level.warning:
        return 'WARN';
      case Level.error:
        return 'ERROR';
      case Level.fatal:
        return 'FATAL';
      default:
        return level.name.toUpperCase();
    }
  }
}

/// Creates the application logger with structured JSON output.
/// Pass this instance to all services and cubits.
Logger createAppLogger() {
  return Logger(
    printer: StructuredLogPrinter(),
    level: Level.debug,
  );
}
