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
    logger.i('[SupabaseService] subscribing to room | roomCode=$roomCode');
    _channel = Supabase.instance.client
        .channel('room:$roomCode')
        .onBroadcast(event: 'room:state', callback: (p) {
          logger.i('[SupabaseService] recv room:state | roomCode=$roomCode payloadKeys=${p.keys.toList()}');
          _emit(RealtimeEventType.roomState, p);
        })
        .onBroadcast(event: 'game:start', callback: (p) {
          logger.i('[SupabaseService] recv game:start | roomCode=$roomCode');
          _emit(RealtimeEventType.gameStart, p);
        })
        .onBroadcast(
          event: 'question:new',
          callback: (p) {
            if (p.containsKey('correct_answer_index')) {
              logger.e(
                '[SupabaseService] SECURITY VIOLATION: correct_answer_index in question:new!',
              );
            }
            logger.i('[SupabaseService] recv question:new | roomCode=$roomCode questionId=${p['id']}');
            _emit(RealtimeEventType.questionNew, p);
          },
        )
        .onBroadcast(
          event: 'round:update',
          callback: (p) {
            logger.i('[SupabaseService] recv round:update | roomCode=$roomCode');
            _emit(RealtimeEventType.roundUpdate, p);
          },
        )
        .onBroadcast(
          event: 'round:reveal',
          callback: (p) {
            logger.i('[SupabaseService] recv round:reveal | roomCode=$roomCode correctIndex=${p['correctIndex']}');
            _emit(RealtimeEventType.roundReveal, p);
          },
        )
        .onBroadcast(event: 'game:end', callback: (p) {
          logger.i('[SupabaseService] recv game:end | roomCode=$roomCode');
          _emit(RealtimeEventType.gameEnd, p);
        })
        .onBroadcast(
          event: 'player:disconnected',
          callback: (p) {
            logger.i('[SupabaseService] recv player:disconnected | roomCode=$roomCode playerId=${p['playerId']}');
            _emit(RealtimeEventType.playerDisconnected, p);
          },
        )
        .subscribe((status, err) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            logger.i('[SupabaseService] subscribed successfully | roomCode=$roomCode');
          } else if (err != null) {
            logger.e('[SupabaseService] subscription error | roomCode=$roomCode err=$err');
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
