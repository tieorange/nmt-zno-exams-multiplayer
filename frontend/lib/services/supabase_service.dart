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

  void subscribeToRoom(String roomCode) {
    logger.i('[SupabaseService] subscribing to room:$roomCode');
    _channel = Supabase.instance.client
        .channel('room:$roomCode')
        .onBroadcast(event: 'room:state', callback: (p) => _emit(RealtimeEventType.roomState, p))
        .onBroadcast(event: 'game:start', callback: (p) => _emit(RealtimeEventType.gameStart, p))
        .onBroadcast(
          event: 'question:new',
          callback: (p) {
            if (p.containsKey('correct_answer_index')) {
              logger.e(
                '[SupabaseService] SECURITY VIOLATION: correct_answer_index in question:new!',
              );
            }
            _emit(RealtimeEventType.questionNew, p);
          },
        )
        .onBroadcast(
          event: 'round:update',
          callback: (p) => _emit(RealtimeEventType.roundUpdate, p),
        )
        .onBroadcast(
          event: 'round:reveal',
          callback: (p) => _emit(RealtimeEventType.roundReveal, p),
        )
        .onBroadcast(event: 'game:end', callback: (p) => _emit(RealtimeEventType.gameEnd, p))
        .onBroadcast(
          event: 'player:disconnected',
          callback: (p) => _emit(RealtimeEventType.playerDisconnected, p),
        )
        .subscribe((status, err) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            logger.i('[SupabaseService] subscribed to room:$roomCode');
          } else if (err != null) {
            logger.e('[SupabaseService] ERROR subscription | err=$err');
          }
        });
  }

  void _emit(RealtimeEventType type, Map<String, dynamic> data) {
    logger.i('[SupabaseService] event | type=${type.name}');
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
