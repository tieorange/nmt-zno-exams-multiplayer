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
              ? Map<String, dynamic>.from(raw as Map)
              : <String, dynamic>{'raw': raw};

      final payload = rawMap['payload'];
      final p =
          payload is Map ? Map<String, dynamic>.from(payload as Map) : rawMap;

      logger.d('[SupabaseService] RAW $eventName | raw:\n$rawMap');
      sideEffect?.call(p);
      final extraLog = extra != null ? ' ${extra(p)}' : '';
      logger.i(
        '[SupabaseService] recv $eventName | roomCode=$roomCode$extraLog rawKeys=${rawMap.keys.toList()}',
      );
      _emit(eventType, p);
    };
  }

  void subscribeToRoom(String roomCode) {
    logger.i('[SupabaseService] subscribing to room | roomCode=$roomCode');
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
                logger.e(
                  '[SupabaseService] SECURITY VIOLATION: correct_answer_index in question:new!',
                );
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
            logger.i(
              '[SupabaseService] subscribed successfully | roomCode=$roomCode',
            );
          } else if (err != null) {
            logger.e(
              '[SupabaseService] subscription error | roomCode=$roomCode err=$err',
            );
          }
        });
  }

  void _emit(RealtimeEventType type, Map<String, dynamic> data) {
    logger.i(
      '[SupabaseService] event emitted | type=${type.name} keys=${data.keys.toList()}',
    );
    _controller.add(RealtimeEvent(type, data));
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
    logger.i('[SupabaseService] unsubscribed');
  }

  void dispose() {
    unsubscribe();
    _controller.close();
  }
}
