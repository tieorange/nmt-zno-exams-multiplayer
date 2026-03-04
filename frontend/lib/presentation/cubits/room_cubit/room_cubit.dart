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
  late StreamSubscription<RealtimeEvent> _sub;
  Timer? _heartbeatTimer;

  // Set on joinRoom() response — used by QuizCubit to identify "my" answers
  String? myPlayerId;
  String? myName;
  bool myIsCreator = false;

  bool _hasStartRequest = false;

  // Pending game snapshot for rejoin recovery — consumed once by main.dart coordinator
  Map<String, dynamic>? _pendingSnapshot;
  Map<String, dynamic>? consumePendingSnapshot() {
    final s = _pendingSnapshot;
    _pendingSnapshot = null;
    return s;
  }

  RoomCubit({required this.supabaseService, required this.apiService, required this.logger})
    : super(const RoomState()) {
    _sub = supabaseService.events.listen(_handleEvent);
  }

  Future<void> joinRoom(String roomCode) async {
    _hasStartRequest = false;
    logger.i('[RoomCubit] joining room | roomCode=$roomCode');
    try {
      // Subscribe to Supabase Realtime BEFORE calling REST join,
      // so we don't miss the room:state broadcast that fires on join.
      supabaseService.subscribeToRoom(roomCode.toUpperCase());

      final result = await apiService.joinRoom(roomCode);
      myPlayerId = result['playerId'] as String;
      myName = result['name'] as String;
      myIsCreator = result['isCreator'] as bool? ?? false;
      logger.i({
        'feature': 'RoomCubit',
        'event': 'room.joined',
        'roomCode': roomCode.toUpperCase(),
        'playerId': myPlayerId,
        'name': myName,
        'isCreator': myIsCreator,
        'outcome': 'success',
      });

      // Immediately update local state with our player info to avoid race conditions
      // where the realtime broadcast hasn't arrived yet
      final myPlayer = PlayerModel(
        id: myPlayerId!,
        name: myName!,
        color: result['color'] as String? ?? '#4ECDC4',
        score: 0,
        isCreator: myIsCreator,
      );

      final currentPlayers = List<PlayerModel>.from(state.players);
      final index = currentPlayers.indexWhere((p) => p.id == myPlayerId);
      if (index >= 0) {
        currentPlayers[index] = myPlayer;
      } else {
        currentPlayers.add(myPlayer);
      }

      // The join response includes status and currentQuestion (on rejoin) so we
      // can bootstrap QuizCubit immediately without an extra HTTP round-trip.
      final statusStr = result['status'] as String? ?? 'waiting';
      final resolvedStatus = switch (statusStr) {
        'playing' => RoomStatus.playing,
        'finished' => RoomStatus.finished,
        _ => RoomStatus.waiting,
      };
      final currentQuestion = result['currentQuestion'] as Map<String, dynamic>?;
      if (currentQuestion != null) {
        _pendingSnapshot = currentQuestion;
        logger.i(
          '[RoomCubit] rejoin snapshot from join response | questionId=${currentQuestion['id']}',
        );
      }

      emit(
        state.copyWith(
          code: roomCode.toUpperCase(),
          players: currentPlayers,
          status: resolvedStatus,
        ),
      );

      // Start heartbeat — backend disconnects players after 60s of silence
      _startHeartbeat(roomCode.toUpperCase());
    } catch (e, st) {
      logger.e(
        {
          'feature': 'RoomCubit',
          'event': 'room.join.failed',
          'roomCode': roomCode,
          'currentStatus': state.status.name,
          'outcome': 'failure',
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
      emit(state.copyWith(status: RoomStatus.error, errorMessage: e.toString()));
    }
  }

  void _startHeartbeat(String roomCode) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (myPlayerId != null) {
        apiService.heartbeat(roomCode, myPlayerId!);
      }
    });
  }

  Future<void> startGame() async {
    if (myPlayerId == null || _hasStartRequest) return;
    if (state.status != RoomStatus.waiting) return;
    _hasStartRequest = true;
    emit(state.copyWith(isStartingGame: true, errorMessage: null));
    logger.i({
      'feature': 'RoomCubit',
      'event': 'game.start.attempt',
      'roomCode': state.code,
      'playerId': myPlayerId,
      'playerCount': state.players.length,
    });
    try {
      await apiService.startGame(state.code, myPlayerId!);
      await _prefetchCurrentQuestionSnapshot(state.code);
      emit(state.copyWith(status: RoomStatus.playing, isStartingGame: false));
    } catch (e, st) {
      final err = e.toString();
      if (err.contains('Гра вже почалась') || err.contains('game_already_started')) {
        logger.w({
          'feature': 'RoomCubit',
          'event': 'game.start.already_started',
          'roomCode': state.code,
        });
        await _prefetchCurrentQuestionSnapshot(state.code);
        emit(state.copyWith(status: RoomStatus.playing, isStartingGame: false));
        return;
      }
      _hasStartRequest = false;
      logger.e(
        {
          'feature': 'RoomCubit',
          'event': 'game.start.failed',
          'roomCode': state.code,
          'currentStatus': state.status.name,
          'outcome': 'failure',
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
      emit(
        state.copyWith(status: RoomStatus.error, errorMessage: e.toString(), isStartingGame: false),
      );
    }
  }

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.roomState:
        _handleRoomState(event.data);
        break;
      case RealtimeEventType.gameStart:
        unawaited(_handleGameStartEvent());
        break;
      case RealtimeEventType.playerDisconnected:
        final playerId = event.data['playerId'] as String?;
        logger.w('[RoomCubit] player disconnected | playerId=$playerId');
        if (playerId != null) {
          emit(state.copyWith(players: state.players.where((p) => p.id != playerId).toList()));
        }
        break;
      case RealtimeEventType.roundReveal:
        // Update all player scores from the event
        final scoreMap = event.data['scores'] as Map<String, dynamic>? ?? {};
        final updatedPlayers = state.players.map((p) {
          if (scoreMap.containsKey(p.id)) {
            return PlayerModel(
              id: p.id,
              name: p.name,
              color: p.color,
              score: scoreMap[p.id] as int,
              isCreator: p.isCreator,
            );
          }
          return p;
        }).toList();

        emit(state.copyWith(players: updatedPlayers));
        break;
      default:
        break;
    }
  }

  Future<void> _handleGameStartEvent() async {
    logger.i('[RoomCubit] game:start received | transitioning to playing');
    await _prefetchCurrentQuestionSnapshot(state.code);
    emit(state.copyWith(status: RoomStatus.playing, isStartingGame: false));
  }

  Future<void> _prefetchCurrentQuestionSnapshot(String roomCode) async {
    if (roomCode.isEmpty) return;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final room = await apiService.getRoomState(roomCode);
        final currentQuestion = room['currentQuestion'] as Map<String, dynamic>?;
        if (currentQuestion != null) {
          _pendingSnapshot = currentQuestion;
          logger.i(
            '[RoomCubit] snapshot loaded | roomCode=$roomCode questionId=${currentQuestion['id']} attempt=$attempt',
          );
          return;
        }
        logger.w('[RoomCubit] snapshot missing | roomCode=$roomCode attempt=$attempt');
      } catch (e) {
        logger.w('[RoomCubit] snapshot fetch failed | roomCode=$roomCode attempt=$attempt err=$e');
      }
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// REST fallback sync for lobby clients in case realtime broadcasts are missed.
  Future<void> syncRoomState() async {
    if (state.code.isEmpty) return;
    try {
      final room = await apiService.getRoomState(state.code);
      final statusStr = room['status'] as String? ?? 'waiting';
      final status = switch (statusStr) {
        'playing' => RoomStatus.playing,
        'finished' => RoomStatus.finished,
        _ => RoomStatus.waiting,
      };
      final players = (room['players'] as List? ?? [])
          .map((p) => PlayerModel.fromJson(p as Map<String, dynamic>))
          .toList();

      final currentQuestion = room['currentQuestion'] as Map<String, dynamic>?;
      if (currentQuestion != null) {
        _pendingSnapshot = currentQuestion;
      }

      if (status == RoomStatus.waiting) {
        _hasStartRequest = false;
      }

      logger.i({
        'feature': 'RoomCubit',
        'event': 'room.sync',
        'roomCode': state.code,
        'roomStatus': statusStr,
        'playerCount': players.length,
      });
      emit(
        state.copyWith(
          code: room['code'] as String? ?? state.code,
          subject: room['subject'] as String? ?? state.subject,
          status: status,
          maxPlayers: room['maxPlayers'] as int? ?? state.maxPlayers,
          players: players,
          isStartingGame: status == RoomStatus.waiting ? false : state.isStartingGame,
        ),
      );
    } catch (e, st) {
      logger.w(
        {
          'feature': 'RoomCubit',
          'event': 'room.sync.failed',
          'roomCode': state.code,
          'currentStatus': state.status.name,
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
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
    if (status == RoomStatus.waiting) {
      _hasStartRequest = false;
    }
    logger.i('[RoomCubit] room:state | status=$statusStr players=${players.length}');
    emit(
      state.copyWith(
        code: data['code'] as String? ?? state.code,
        subject: data['subject'] as String? ?? state.subject,
        status: status,
        maxPlayers: data['maxPlayers'] as int? ?? state.maxPlayers,
        players: players,
        isStartingGame: status == RoomStatus.waiting ? false : state.isStartingGame,
      ),
    );
  }

  void leaveRoom() {
    logger.i('[RoomCubit] leaving room | roomCode=${state.code}');
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _hasStartRequest = false;
    _pendingSnapshot = null;
    myPlayerId = null;
    myName = null;
    myIsCreator = false;
    supabaseService.unsubscribe();
    emit(const RoomState());
  }

  @override
  Future<void> close() {
    _sub.cancel();
    _heartbeatTimer?.cancel();
    supabaseService.unsubscribe();
    return super.close();
  }
}
