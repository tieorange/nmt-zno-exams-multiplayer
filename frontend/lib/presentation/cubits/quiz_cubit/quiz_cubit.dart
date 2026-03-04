import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../data/models/question_model.dart';
import '../../../services/supabase_service.dart';
import '../../../services/api_service.dart';
import 'quiz_state.dart';

class QuizCubit extends Cubit<QuizState> {
  final SupabaseService supabaseService;
  final ApiService apiService;
  final Logger logger;
  late StreamSubscription<RealtimeEvent> _sub;
  Timer? _timer;
  Timer? _pollTimer;
  ClientQuestion? _currentQuestion;
  String? _myPlayerId;
  String? _roomCode;
  int _questionIndex = 0;
  int _totalQuestions = 10;
  // Bug 8 fix: driven by game:start payload (timerMs) instead of hardcoded 5 min
  int _timerMs = 5 * 60 * 1000;

  QuizCubit({required this.supabaseService, required this.apiService, required this.logger})
    : super(const QuizInitial()) {
    _sub = supabaseService.events.listen(_handleEvent);
  }

  void setContext(String myPlayerId, String roomCode) {
    _myPlayerId = myPlayerId;
    _roomCode = roomCode;
  }

  /// Starts a 2-second polling fallback that fetches round state via REST.
  /// This catches missed Supabase Realtime events (e.g. on LAN via `make iphone`).
  /// Safe to call multiple times — cancels any existing poll timer first.
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollRoundState();
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Bootstrap quiz state from a server snapshot on rejoin.
  /// Restores the current question and starts the local countdown timer.
  void bootstrapFromSnapshot(Map<String, dynamic> snapshot) {
    try {
      _currentQuestion = ClientQuestion.fromJson(snapshot);
      // Backend questionIndex is 0-based; QuizCubit._questionIndex is 1-based for display.
      // Add 1 to match what _handleNewQuestion would have set.
      final rawIndex = snapshot['questionIndex'] as int? ?? 0;
      _questionIndex = rawIndex + 1;
      // Restore totalQuestions from snapshot so "Q x/N" shows correctly without game:start.
      _totalQuestions = snapshot['totalQuestions'] as int? ?? _totalQuestions;
      // Sync timer duration from snapshot (overrides the game:start value we may have missed).
      _timerMs = snapshot['timerMs'] as int? ?? _timerMs;

      // Compute how much time is actually left on the server's timer so the
      // rejoining player sees the correct countdown rather than a full reset.
      final roundStartedAtStr = snapshot['roundStartedAt'] as String?;
      final Duration remaining;
      if (roundStartedAtStr != null) {
        final roundStartedAt = DateTime.parse(roundStartedAtStr);
        final elapsed = DateTime.now().difference(roundStartedAt);
        final remainingMs = (_timerMs - elapsed.inMilliseconds).clamp(0, _timerMs);
        remaining = Duration(milliseconds: remainingMs);
      } else {
        remaining = Duration(milliseconds: _timerMs);
      }

      logger.i({
        'feature': 'QuizCubit',
        'event': 'quiz.bootstrap.from_snapshot',
        'questionId': _currentQuestion!.id,
        'questionIndex': _questionIndex,
        'totalQuestions': _totalQuestions,
        'remainingMs': remaining.inMilliseconds,
        'roomCode': _roomCode,
      });
      emit(
        QuizQuestion(
          question: _currentQuestion!,
          questionIndex: _questionIndex,
          totalQuestions: _totalQuestions,
          timeRemaining: remaining,
          totalTime: Duration(milliseconds: _timerMs),
        ),
      );
      _startTimer(remaining);
    } catch (e, st) {
      logger.e(
        {
          'feature': 'QuizCubit',
          'event': 'quiz.bootstrap.failed',
          'roomCode': _roomCode,
          'currentState': state.runtimeType.toString(),
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Fallback recovery for cases when realtime `question:new` was missed.
  /// If the room is already playing and has a currentQuestion snapshot,
  /// bootstrap quiz state from REST.
  Future<void> recoverFromRoomSnapshot(String roomCode) async {
    if (state is QuizQuestion) return;
    try {
      final room = await apiService.getRoomState(roomCode);
      final snapshot = room['currentQuestion'] as Map<String, dynamic>?;
      if (snapshot == null) {
        logger.w('[QuizCubit] recoverFromRoomSnapshot | no currentQuestion roomCode=$roomCode');
        return;
      }
      logger.i(
        '[QuizCubit] recoverFromRoomSnapshot | roomCode=$roomCode questionId=${snapshot['id']}',
      );
      bootstrapFromSnapshot(snapshot);
    } catch (e) {
      logger.w('[QuizCubit] recoverFromRoomSnapshot failed | roomCode=$roomCode err=$e');
    }
  }

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.gameStart:
        _totalQuestions = event.data['totalQuestions'] as int? ?? 10;
        // Bug 7 fix: reset question index to 0 on every game start (handles restarts)
        _questionIndex = 0;
        // Bug 8 fix: read timer duration from server so we stay in sync with ROUND_TIMER_MS
        _timerMs = event.data['timerMs'] as int? ?? (5 * 60 * 1000);
        logger.i({
          'feature': 'QuizCubit',
          'event': 'game.start.received',
          'roomCode': _roomCode,
          'totalQuestions': _totalQuestions,
          'timerMs': _timerMs,
        });
        break;
      case RealtimeEventType.questionNew:
        _handleNewQuestion(event.data);
        break;
      case RealtimeEventType.roundUpdate:
        _handleRoundUpdate(event.data);
        break;
      case RealtimeEventType.roundReveal:
        _handleReveal(event.data);
        break;
      case RealtimeEventType.gameEnd:
        logger.i('[QuizCubit] game ended | scoreboard=${event.data['scoreboard']}');
        _timer?.cancel();
        emit(
          QuizGameEnded(
            scoreboard: List<Map<String, dynamic>>.from(event.data['scoreboard'] as List),
          ),
        );
        break;
      default:
        logger.w('[QuizCubit] Unknown event received | type=${event.type}');
        break;
    }
  }

  void _handleNewQuestion(Map<String, dynamic> data) {
    _stopPolling(); // Cancel any reveal-state poll when realtime delivers question:new
    _questionIndex++;
    try {
      _currentQuestion = ClientQuestion.fromJson(data);
      logger.i({
        'feature': 'QuizCubit',
        'event': 'question.new.received',
        'roomCode': _roomCode,
        'questionId': _currentQuestion!.id,
        'choicesCount': _currentQuestion!.choices.length,
        'questionIndex': _questionIndex,
        'totalQuestions': _totalQuestions,
        'timerMs': _timerMs,
      });

      emit(
        QuizQuestion(
          question: _currentQuestion!,
          questionIndex: _questionIndex,
          totalQuestions: _totalQuestions,
          timeRemaining: Duration(milliseconds: _timerMs),
          totalTime: Duration(milliseconds: _timerMs),
        ),
      );
      _startTimer();
    } catch (e, st) {
      logger.e(
        {
          'feature': 'QuizCubit',
          'event': 'question.parse.failed',
          'roomCode': _roomCode,
          'questionIndex': _questionIndex,
          'currentState': state.runtimeType.toString(),
          'faultyDataKeys': data.keys.toList(),
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
      emit(QuizError('Failed to load question: $e'));
    }
  }

  void _startTimer([Duration? initialRemaining]) {
    _timer?.cancel();
    var remaining = initialRemaining ?? Duration(milliseconds: _timerMs);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining -= const Duration(seconds: 1);
      if (remaining.isNegative) {
        _timer?.cancel();
        return;
      }
      final s = state;
      if (s is QuizQuestion) emit(s.copyWith(timeRemaining: remaining));
    });
  }

  void _handleRoundUpdate(Map<String, dynamic> data) {
    final raw = data['playerAnswers'] as Map<String, dynamic>? ?? {};
    final answers = raw.map((k, v) => MapEntry(k, v as int?));
    logger.i('[QuizCubit] round:update received | answeredPlayers=${answers.length}');
    final s = state;
    if (s is QuizQuestion) emit(s.copyWith(playerAnswers: answers));
  }

  /// Polling fallback: fetch round state from REST and apply any missed events.
  /// Handles two scenarios:
  ///   1. QuizQuestion state  → apply missed round:update / round:reveal
  ///   2. QuizReveal state    → detect when creator presses “Next Question” and
  ///                            bootstrap the new question (missed question:new)
  Future<void> _pollRoundState() async {
    if (_roomCode == null) return;
    final s = state;

    // SCENARIO 2: Stuck on reveal screen — poll for next question
    if (s is QuizReveal) {
      await _pollForNextQuestion(s.question.id);
      return;
    }

    // SCENARIO 3: Stuck on results screen — poll for game restart
    if (s is QuizGameEnded) {
      await _pollForGameRestart();
      return;
    }

    // Stop for any other non-question state (loading, error)
    if (s is! QuizQuestion) {
      _stopPolling();
      return;
    }
    try {
      final data = await apiService.getRoundState(_roomCode!);

      // If pendingReveal is present, the round has been revealed — trigger reveal
      final pendingReveal = data['pendingReveal'] as Map<String, dynamic>?;
      if (pendingReveal != null) {
        logger.i('[QuizCubit] poll detected pendingReveal | roomCode=$_roomCode');
        _stopPolling();
        _handleReveal(pendingReveal);
        return;
      }

      // Apply live playerAnswers update (for chip animations)
      final rawAnswers = data['playerAnswers'];
      if (rawAnswers is Map) {
        final answers = rawAnswers.map((k, v) => MapEntry(k.toString(), v as int?));
        final currentS = state;
        if (currentS is QuizQuestion &&
            answers.isNotEmpty &&
            !_mapsEqual(answers, currentS.playerAnswers)) {
          logger.i(
            '[QuizCubit] poll applied round:update | answeredCount=${answers.values.where((v) => v != null).length}',
          );
          emit(currentS.copyWith(playerAnswers: answers));
        }
      }
    } catch (e) {
      // Polling errors are silent — network blips should not crash the app
      logger.d('[QuizCubit] _pollRoundState error (silent) | $e');
    }
  }

  /// REST fallback: detect when the creator restarts the game from the results screen.
  Future<void> _pollForGameRestart() async {
    if (_roomCode == null) return;
    try {
      final room = await apiService.getRoomState(_roomCode!);
      if (room['status'] == 'playing') {
        final snapshot = room['currentQuestion'] as Map<String, dynamic>?;
        if (snapshot != null) {
          logger.i('[QuizCubit] poll detected game restart | roomCode=$_roomCode');
          _stopPolling();
          _questionIndex = 0; // reset index for new game
          bootstrapFromSnapshot(snapshot); // emits QuizQuestion
          startPolling();
        }
      }
    } catch (e) {
      logger.d('[QuizCubit] _pollForGameRestart error (silent) | $e');
    }
  }

  bool _mapsEqual(Map<String, int?> a, Map<String, int?> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  /// Polls GET /rooms/:code to detect when the creator advances to the next
  /// question (missed question:new broadcast). Bootstraps from snapshot if so.
  Future<void> _pollForNextQuestion(String revealedQuestionId) async {
    if (_roomCode == null) return;
    try {
      final room = await apiService.getRoomState(_roomCode!);

      if (room['status'] == 'finished') {
        logger.i('[QuizCubit] poll detected game end | roomCode=$_roomCode');
        _stopPolling();

        final playersList = room['players'] as List? ?? [];
        final scoreboard = playersList.map((p) => Map<String, dynamic>.from(p as Map)).toList();
        scoreboard.sort((a, b) => (b['score'] as int? ?? 0).compareTo(a['score'] as int? ?? 0));
        for (int i = 0; i < scoreboard.length; i++) {
          scoreboard[i]['rank'] = i + 1;
        }

        _timer?.cancel();
        emit(QuizGameEnded(scoreboard: scoreboard));
        return;
      }

      final snapshot = room['currentQuestion'] as Map<String, dynamic>?;
      if (snapshot == null) return;
      final newQId = snapshot['id'] as String?;
      if (newQId != null && newQId != revealedQuestionId) {
        logger.i('[QuizCubit] poll detected new question | old=$revealedQuestionId new=$newQId');
        _stopPolling();
        bootstrapFromSnapshot(snapshot); // emits QuizQuestion
        startPolling(); // start round polling for new question
      }
    } catch (e) {
      logger.d('[QuizCubit] _pollForNextQuestion error (silent) | $e');
    }
  }

  void _handleReveal(Map<String, dynamic> data) {
    _timer?.cancel();
    _stopPolling(); // Stop polling once reveal is handled

    // Guard: if we missed question:new, we can't show the reveal properly
    if (_currentQuestion == null) {
      logger.w('[QuizCubit] round:reveal received but _currentQuestion is null - ignoring');
      return;
    }

    final correctIndex = data['correctIndex'] as int;
    final raw = data['playerAnswers'] as Map<String, dynamic>? ?? {};
    final answers = raw.map((k, v) => MapEntry(k, v as int?));
    final scores = Map<String, int>.from(data['scores'] as Map);
    final scoreDeltas = Map<String, int>.from(data['scoreDeltas'] as Map? ?? {});
    final myAnswer = _myPlayerId != null ? answers[_myPlayerId] : null;
    final myScoreGained = _myPlayerId != null ? scoreDeltas[_myPlayerId] : null;

    logger.i({
      'feature': 'QuizCubit',
      'event': 'round.reveal.received',
      'roomCode': _roomCode,
      'questionIndex': _questionIndex,
      'correctIndex': correctIndex,
      'myAnswer': myAnswer,
      'isCorrect': myAnswer == correctIndex,
      'scoreGained': myScoreGained ?? 0,
    });
    emit(
      QuizReveal(
        question: _currentQuestion!,
        correctIndex: correctIndex,
        playerAnswers: answers,
        scores: scores,
        myAnswer: myAnswer,
        myScoreGained: myScoreGained,
      ),
    );
  }

  Future<void> nextQuestion() async {
    if (_myPlayerId == null || _roomCode == null) return;
    logger.i('[QuizCubit] nextQuestion | roomCode=$_roomCode');
    try {
      await apiService.nextQuestion(_roomCode!, _myPlayerId!);
    } catch (e, st) {
      logger.e(
        {
          'feature': 'QuizCubit',
          'event': 'quiz.next_question.failed',
          'roomCode': _roomCode,
          'currentState': state.runtimeType.toString(),
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> submitAnswer(int answerIndex) async {
    final s = state;
    if (s is! QuizQuestion || _myPlayerId == null || _roomCode == null) return;
    logger.i(
      '[QuizCubit] answer submitted | questionId=${s.question.id} selectedIndex=$answerIndex',
    );
    // Optimistic UI update — lock button immediately
    emit(s.copyWith(myAnswer: answerIndex));
    try {
      // Bug 12 fix: wrap in try/catch and revert optimistic update on failure
      await apiService.submitAnswer(_roomCode!, _myPlayerId!, s.question.id, answerIndex);
    } catch (e, st) {
      logger.e(
        {
          'feature': 'QuizCubit',
          'event': 'quiz.submit_answer.failed',
          'roomCode': _roomCode,
          'questionId': s.question.id,
          'answerIndex': answerIndex,
          'questionIndex': _questionIndex,
          'error': e.toString(),
        },
        error: e,
        stackTrace: st,
      );
      // Revert the optimistic update so the player can try again
      emit(s.copyWith(myAnswer: null));
    }
  }

  void reset() {
    logger.i('[QuizCubit] resetting state');
    _timer?.cancel();
    _timer = null;
    _stopPolling();
    _currentQuestion = null;
    _myPlayerId = null;
    _roomCode = null;
    _questionIndex = 0;
    emit(const QuizInitial());
  }

  @override
  Future<void> close() {
    logger.i('[QuizCubit] closing');
    _sub.cancel();
    _timer?.cancel();
    _stopPolling();
    return super.close();
  }
}
