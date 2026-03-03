import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

/// Handles all client→server REST calls to the Node.js backend.
class ApiService {
  final String baseUrl;
  final Logger logger;
  static const _uuid = Uuid();

  /// Stable per-session ID — generated once per app launch.
  /// Sent on join so the backend can reconnect the same player
  /// if the user refreshes or opens a duplicate tab.
  static final String _sessionId = _generateSessionId();

  static String _generateSessionId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(16, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  ApiService({required this.logger})
    : baseUrl = const String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  /// Logs request start, executes [fn], then logs finish with durationMs + outcome.
  /// The same [requestId] is emitted on both lines for easy grep/AI correlation.
  Future<T> _traced<T>(
    String feature,
    String method,
    String endpoint,
    Future<T> Function(String requestId) fn,
  ) async {
    final requestId = _uuid.v4();
    final start = DateTime.now();
    logger.i({
      'feature': feature,
      'event': 'api.request.start',
      'requestId': requestId,
      'method': method,
      'endpoint': endpoint,
    });
    try {
      final result = await fn(requestId);
      final durationMs = DateTime.now().difference(start).inMilliseconds;
      logger.i({
        'feature': feature,
        'event': 'api.request.finish',
        'requestId': requestId,
        'method': method,
        'endpoint': endpoint,
        'durationMs': durationMs,
        'outcome': 'success',
      });
      return result;
    } catch (e, st) {
      final durationMs = DateTime.now().difference(start).inMilliseconds;
      logger.e({
        'feature': feature,
        'event': 'api.request.failed',
        'requestId': requestId,
        'method': method,
        'endpoint': endpoint,
        'durationMs': durationMs,
        'outcome': 'failure',
        'error': e.toString(),
      }, error: e, stackTrace: st);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createRoom(String subject, int maxPlayers) {
    const endpoint = '/api/rooms';
    return _traced('ApiService', 'POST', endpoint, (_) async {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'subject': subject, 'maxPlayers': maxPlayers}),
      );
      if (res.statusCode != 201) {
        throw Exception('createRoom failed (${res.statusCode}): ${res.body}');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
      // Returns: { code: 'A9X' }
    });
  }

  Future<Map<String, dynamic>> joinRoom(String roomCode) {
    final endpoint = '/api/rooms/${roomCode.toUpperCase()}/join';
    return _traced('ApiService', 'POST', endpoint, (_) async {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'sessionId': _sessionId}),
      );
      if (res.statusCode != 200) {
        throw Exception('joinRoom failed (${res.statusCode}): ${res.body}');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
      // Returns: { playerId, name, color, isCreator }
    });
  }

  Future<void> startGame(String roomCode, String playerId) {
    final endpoint = '/api/rooms/${roomCode.toUpperCase()}/start';
    return _traced('ApiService', 'POST', endpoint, (_) async {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': playerId}),
      );
      if (res.statusCode != 200) {
        throw Exception('startGame failed (${res.statusCode}): ${res.body}');
      }
    });
  }

  Future<void> submitAnswer(
    String roomCode,
    String playerId,
    String questionId,
    int answerIndex,
  ) {
    final endpoint = '/api/rooms/${roomCode.toUpperCase()}/answer';
    return _traced('ApiService', 'POST', endpoint, (_) async {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'playerId': playerId,
          'questionId': questionId,
          'answerIndex': answerIndex,
        }),
      );
      if (res.statusCode != 200) {
        throw Exception('submitAnswer failed (${res.statusCode}): ${res.body}');
      }
    });
  }

  Future<void> heartbeat(String roomCode, String playerId) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': playerId}),
      );
    } catch (_) {
      // Heartbeat failures are silent — network blip should not crash the app
    }
  }

  Future<List<Map<String, dynamic>>> getSubjects() {
    const endpoint = '/api/subjects';
    return _traced('ApiService', 'GET', endpoint, (_) async {
      final res = await http.get(Uri.parse('$baseUrl$endpoint'));
      if (res.statusCode != 200) {
        throw Exception('getSubjects failed (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['subjects'] as List);
    });
  }

  Future<void> restartGame(String roomCode, String playerId) {
    final endpoint = '/api/rooms/${roomCode.toUpperCase()}/restart';
    return _traced('ApiService', 'POST', endpoint, (_) async {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': playerId}),
      );
      if (res.statusCode != 200) {
        throw Exception('restartGame failed (${res.statusCode}): ${res.body}');
      }
    });
  }

  Future<Map<String, dynamic>> getRoomState(String roomCode) {
    final endpoint = '/api/rooms/${roomCode.toUpperCase()}';
    return _traced('ApiService', 'GET', endpoint, (_) async {
      final res = await http.get(Uri.parse('$baseUrl$endpoint'));
      if (res.statusCode != 200) {
        throw Exception('getRoomState failed (${res.statusCode}): ${res.body}');
      }
      return jsonDecode(res.body) as Map<String, dynamic>;
      // Returns: { code, subject, status, maxPlayers, currentQuestionIndex, currentQuestion?, players[] }
    });
  }

  Future<void> nextQuestion(String roomCode, String playerId) {
    final endpoint = '/api/rooms/${roomCode.toUpperCase()}/next-question';
    return _traced('ApiService', 'POST', endpoint, (_) async {
      final res = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'playerId': playerId}),
      );
      if (res.statusCode != 200) {
        throw Exception('nextQuestion failed (${res.statusCode}): ${res.body}');
      }
    });
  }
}
