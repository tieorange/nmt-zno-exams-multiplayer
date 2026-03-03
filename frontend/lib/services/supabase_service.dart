import 'dart:async';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Server→client event types (all delivered via Supabase Realtime Broadcast)
enum RealtimeEventType {
  roomState,
  gameStart,
  questionNew,
  roundUpdate,
  roundReveal,
  gameEnd,
  playerDisconnected,
}

class RealtimeEvent {
  final RealtimeEventType type;
  final Map<String, dynamic> data;
  const RealtimeEvent(this.type, this.data);
}

class SupabaseService {
  final Logger logger;
  final _controller = StreamController<RealtimeEvent>.broadcast();
  RealtimeChannel? _channel;

  Stream<RealtimeEvent> get events => _controller.stream;

  SupabaseService({required this.logger});

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: const String.fromEnvironment('SUPABASE_URL'),
      anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    );
  }

  /// Builds a standard broadcast callback: unwraps the nested payload if present,
  /// logs at debug + info level, runs an optional [sideEffect] (e.g. security checks),
  /// and emits the event onto the shared stream.
  void Function(dynamic) _buildCallback(
    String roomCode,
    RealtimeEventType eventType,
    String eventName, {
    String Function(Map<String, dynamic>)? extra,
    void Function(Map<String, dynamic>)? sideEffect,
  }) {
    return (raw) {
      final rawMap =
          raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{'raw': raw};

      final payload = rawMap['payload'];
      final p =
          payload is Map ? Map<String, dynamic>.from(payload) : rawMap;

      logger.d({
        'feature': 'SupabaseService',
        'event': 'realtime.broadcast.raw',
        'broadcastEvent': eventName,
        'roomCode': roomCode,
        'rawKeys': rawMap.keys.toList(),
      });
      sideEffect?.call(p);
      final extra_ = extra != null ? extra(p) : null;
      logger.i({
        'feature': 'SupabaseService',
        'event': 'realtime.broadcast.received',
        'broadcastEvent': eventName,
        'roomCode': roomCode,
        'payloadKeys': p.keys.toList(),
        if (extra_ != null) 'extra': extra_,
      });
      _emit(eventType, p);
    };
  }

  void subscribeToRoom(String roomCode) {
    logger.i({
      'feature': 'SupabaseService',
      'event': 'realtime.subscribe.start',
      'roomCode': roomCode,
      'hadPreviousChannel': _channel != null,
    });
    if (_channel != null) {
      unsubscribe();
    }
    _channel = Supabase.instance.client
        .channel('room:$roomCode')
        .onBroadcast(
          event: 'room:state',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.roomState,
            'room:state',
            extra: (p) => 'payloadKeys=${p.keys.toList()}',
          ),
        )
        .onBroadcast(
          event: 'game:start',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.gameStart,
            'game:start',
            extra: (p) => 'payloadKeys=${p.keys.toList()}',
          ),
        )
        .onBroadcast(
          event: 'question:new',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.questionNew,
            'question:new',
            extra: (p) => 'questionId=${p['id']}',
            sideEffect: (p) {
              if (p.containsKey('correct_answer_index')) {
                logger.e({
                  'feature': 'SupabaseService',
                  'event': 'security.violation',
                  'broadcastEvent': 'question:new',
                  'roomCode': roomCode,
                  'issue': 'correct_answer_index_leaked_to_client',
                  'payloadKeys': p.keys.toList(),
                });
              }
            },
          ),
        )
        .onBroadcast(
          event: 'round:update',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.roundUpdate,
            'round:update',
          ),
        )
        .onBroadcast(
          event: 'round:reveal',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.roundReveal,
            'round:reveal',
            extra: (p) => 'correctIndex=${p['correctIndex']}',
          ),
        )
        .onBroadcast(
          event: 'game:end',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.gameEnd,
            'game:end',
          ),
        )
        .onBroadcast(
          event: 'player:disconnected',
          callback: _buildCallback(
            roomCode,
            RealtimeEventType.playerDisconnected,
            'player:disconnected',
            extra: (p) => 'playerId=${p['playerId']}',
          ),
        )
        .subscribe((status, err) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            logger.i({
              'feature': 'SupabaseService',
              'event': 'realtime.subscribe.ok',
              'roomCode': roomCode,
              'outcome': 'success',
            });
          } else if (err != null) {
            logger.e({
              'feature': 'SupabaseService',
              'event': 'realtime.subscribe.error',
              'roomCode': roomCode,
              'subscribeStatus': status.name,
              'outcome': 'failure',
              'error': err.toString(),
            });
          } else {
            logger.d({
              'feature': 'SupabaseService',
              'event': 'realtime.subscribe.status',
              'roomCode': roomCode,
              'subscribeStatus': status.name,
            });
          }
        });
  }

  void _emit(RealtimeEventType type, Map<String, dynamic> data) {
    logger.d({
      'feature': 'SupabaseService',
      'event': 'realtime.event.emitted',
      'eventType': type.name,
      'payloadKeys': data.keys.toList(),
    });
    _controller.add(RealtimeEvent(type, data));
  }

  void unsubscribe() {
    logger.i({
      'feature': 'SupabaseService',
      'event': 'realtime.unsubscribe',
      'hadChannel': _channel != null,
    });
    _channel?.unsubscribe();
    _channel = null;
  }

  void dispose() {
    unsubscribe();
    _controller.close();
  }
}
