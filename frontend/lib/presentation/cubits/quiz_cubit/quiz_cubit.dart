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
  ClientQuestion? _currentQuestion;
  String? _myPlayerId;
  String? _roomCode;
  int _questionIndex = 0;
  int _totalQuestions = 10;
  // Bug 8 fix: driven by game:start payload (timerMs) instead of hardcoded 5 min
  int _timerMs = 5 * 60 * 1000;

  QuizCubit({
    required this.supabaseService,
    required this.apiService,
    required this.logger,
  }) : super(const QuizInitial()) {
    _sub = supabaseService.events.listen(_handleEvent);
  }

  void setContext(String myPlayerId, String roomCode) {
    _myPlayerId = myPlayerId;
    _roomCode = roomCode;
  }

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case RealtimeEventType.gameStart:
        _totalQuestions = event.data['totalQuestions'] as int? ?? 10;
        // Bug 7 fix: reset question index to 0 on every game start (handles restarts)
        _questionIndex = 0;
        // Bug 8 fix: read timer duration from server so we stay in sync with ROUND_TIMER_MS
        _timerMs = event.data['timerMs'] as int? ?? (5 * 60 * 1000);
        logger.i(
          '[QuizCubit] game:start received | totalQuestions=$_totalQuestions timerMs=$_timerMs',
        );
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
        logger.i(
          '[QuizCubit] game ended | scoreboard=${event.data['scoreboard']}',
        );
        _timer?.cancel();
        emit(
          QuizGameEnded(
            scoreboard: List<Map<String, dynamic>>.from(
              event.data['scoreboard'] as List,
            ),
          ),
        );
        break;
      default:
        logger.w('[QuizCubit] Unknown event received | type=${event.type}');
        break;
    }
  }

  void _handleNewQuestion(Map<String, dynamic> data) {
    _questionIndex++;
    try {
      _currentQuestion = ClientQuestion.fromJson(data);
      logger.i(
        '[QuizCubit] question:new received | questionId=${_currentQuestion!.id} choicesCount=${_currentQuestion!.choices.length} timerMs=$_timerMs',
      );

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
        '[QuizCubit] Failed to parse question:new data',
        error: e,
        stackTrace: st,
      );
      logger.e('[QuizCubit] Faulty question data: $data');
      emit(QuizError('Failed to load question: $e'));
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // Bug 8 fix: use server-provided timer duration
    var remaining = Duration(milliseconds: _timerMs);
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
    logger.i(
      '[QuizCubit] round:update received | answeredPlayers=${answers.length}',
    );
    final s = state;
    if (s is QuizQuestion) emit(s.copyWith(playerAnswers: answers));
  }

  void _handleReveal(Map<String, dynamic> data) {
    _timer?.cancel();

    // Guard: if we missed question:new, we can't show the reveal properly
    if (_currentQuestion == null) {
      logger.w(
        '[QuizCubit] round:reveal received but _currentQuestion is null - ignoring',
      );
      return;
    }

    final correctIndex = data['correctIndex'] as int;
    final raw = data['playerAnswers'] as Map<String, dynamic>? ?? {};
    final answers = raw.map((k, v) => MapEntry(k, v as int?));
    final scores = Map<String, int>.from(data['scores'] as Map);
    final scoreDeltas = Map<String, int>.from(
      data['scoreDeltas'] as Map? ?? {},
    );
    final myAnswer = _myPlayerId != null ? answers[_myPlayerId] : null;
    final myScoreGained = _myPlayerId != null ? scoreDeltas[_myPlayerId] : null;

    logger.i(
      '[QuizCubit] round:reveal received | correctIndex=$correctIndex myAnswer=$myAnswer isCorrect=${myAnswer == correctIndex} scoreGained=${myScoreGained ?? 0}',
    );
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
    } catch (e) {
      logger.e('[QuizCubit] nextQuestion failed | err=$e');
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
      await apiService.submitAnswer(
        _roomCode!,
        _myPlayerId!,
        s.question.id,
        answerIndex,
      );
    } catch (e) {
      logger.e('[QuizCubit] submitAnswer failed | err=$e');
      // Revert the optimistic update so the player can try again
      emit(s.copyWith(myAnswer: null));
    }
  }

  @override
  Future<void> close() {
    logger.i('[QuizCubit] closing');
    _sub.cancel();
    _timer?.cancel();
    return super.close();
  }
}
