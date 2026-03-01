import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

/// Handles all client→server REST calls to the Node.js backend.
class ApiService {
  final String baseUrl;
  final Logger logger;

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

  Future<Map<String, dynamic>> createRoom(String subject, int maxPlayers) async {
    logger.i('[ApiService] POST /api/rooms | subject=$subject maxPlayers=$maxPlayers');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'subject': subject, 'maxPlayers': maxPlayers}),
    );
    if (res.statusCode != 201) throw Exception('createRoom failed: ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
    // Returns: { code: 'A9X' }
  }

  Future<Map<String, dynamic>> joinRoom(String roomCode) async {
    logger.i('[ApiService] POST /api/rooms/$roomCode/join | sessionId=$_sessionId');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'sessionId': _sessionId}),
    );
    if (res.statusCode != 200) throw Exception('joinRoom failed: ${res.body}');
    return jsonDecode(res.body) as Map<String, dynamic>;
    // Returns: { playerId, name, color, isCreator }
  }

  Future<void> startGame(String roomCode, String playerId) async {
    logger.i('[ApiService] POST /api/rooms/$roomCode/start | playerId=$playerId');
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'playerId': playerId}),
    );
    if (res.statusCode != 200) throw Exception('startGame failed: ${res.body}');
  }

  Future<void> submitAnswer(
    String roomCode,
    String playerId,
    String questionId,
    int answerIndex,
  ) async {
    logger.i(
      '[ApiService] POST /api/rooms/$roomCode/answer | playerId=$playerId answerIndex=$answerIndex',
    );
    final res = await http.post(
      Uri.parse('$baseUrl/api/rooms/${roomCode.toUpperCase()}/answer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'playerId': playerId,
        'questionId': questionId,
        'answerIndex': answerIndex,
      }),
    );
    if (res.statusCode != 200) throw Exception('submitAnswer failed: ${res.body}');
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

  Future<List<Map<String, dynamic>>> getSubjects() async {
    final res = await http.get(Uri.parse('$baseUrl/api/subjects'));
    if (res.statusCode != 200) throw Exception('getSubjects failed: ${res.body}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['subjects'] as List);
  }
}
