import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../data/models/player_model.dart';
import '../../../services/supabase_service.dart';
import '../../../services/api_service.dart';
import 'room_state.dart';

class RoomCubit extends Cubit<RoomState> {
  final SupabaseService supabaseService;
  final ApiService apiService;
  final Logger logger;
  late final StreamSubscription<RealtimeEvent> _sub;

  // Set on joinRoom() response — used by QuizCubit to identify "my" answers
  String? myPlayerId;
  String? myName;
  String? myColor;
  bool myIsCreator = false;

  RoomCubit({
    required this.supabaseService,
    required this.apiService,
    required this.logger,
  }) : super(const RoomState()) {
    _sub = supabaseService.events.listen(_handleEvent);
  }

  Future<void> joinRoom(String roomCode) async {
    logger.i('[RoomCubit] joining room | roomCode=$roomCode');
    try {
      // Subscribe to Supabase Realtime BEFORE calling REST join,
      // so we don't miss the room:state broadcast that fires on join.
      supabaseService.subscribeToRoom(roomCode.toUpperCase());

      final result = await apiService.joinRoom(roomCode);
      myPlayerId = result['playerId'] as String;
      myName = result['name'] as String;
      myColor = result['color'] as String;
      myIsCreator = result['isCreator'] as bool? ?? false;
      logger.i(
          '[RoomCubit] joined | myPlayerId=$myPlayerId name=$myName isCreator=$myIsCreator');
    } catch (e) {
      logger.e('[RoomCubit] joinRoom failed | err=$e');
      emit(state.copyWith(
          status: RoomStatus.error, errorMessage: e.toString()));
    }
  }

  Future<void> startGame() async {
    if (myPlayerId == null) return;
    logger.i('[RoomCubit] starting game | roomCode=${state.code}');
    try {
      await apiService.startGame(state.code, myPlayerId!);
    } catch (e) {
      logger.e('[RoomCubit] startGame failed | err=$e');
      emit(state.copyWith(
          status: RoomStatus.error, errorMessage: e.toString()));
    }
  }

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.roomState:
        _handleRoomState(event.data);
      case RealtimeEventType.gameStart:
        logger.i('[RoomCubit] game:start received | transitioning to playing');
        emit(state.copyWith(status: RoomStatus.playing));
      case RealtimeEventType.playerDisconnected:
        final playerId = event.data['playerId'] as String?;
        logger.w('[RoomCubit] player disconnected | playerId=$playerId');
        if (playerId != null) {
          emit(state.copyWith(
            players: state.players.where((p) => p.id != playerId).toList(),
          ));
        }
      default:
        break;
    }
  }

  void _handleRoomState(Map<String, dynamic> data) {
    final players = (data['players'] as List? ?? [])
        .map((p) => PlayerModel.fromJson(p as Map<String, dynamic>))
        .toList();
    final statusStr = data['status'] as String? ?? 'waiting';
    final status = switch (statusStr) {
      'playing' => RoomStatus.playing,
      'finished' => RoomStatus.finished,
      _ => RoomStatus.waiting,
    };
    logger.i(
        '[RoomCubit] room:state | status=$statusStr players=${players.length}');
    emit(state.copyWith(
      code: data['code'] as String? ?? state.code,
      subject: data['subject'] as String? ?? state.subject,
      status: status,
      maxPlayers: data['maxPlayers'] as int? ?? state.maxPlayers,
      players: players,
    ));
  }

  @override
  Future<void> close() {
    _sub.cancel();
    supabaseService.unsubscribe();
    return super.close();
  }
}
