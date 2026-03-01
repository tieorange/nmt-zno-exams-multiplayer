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
  late final StreamSubscription<RealtimeEvent> _sub;
  Timer? _timer;
  ClientQuestion? _currentQuestion;
  String? _myPlayerId;
  String? _roomCode;
  int _questionIndex = 0;
  int _totalQuestions = 10;

  // Round timer duration — matches ROUND_TIMER_MS on the server (default 5 min)
  static const _roundDuration = Duration(minutes: 5);

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
        _questionIndex = 0;
      case RealtimeEventType.questionNew:
        _handleNewQuestion(event.data);
      case RealtimeEventType.roundUpdate:
        _handleRoundUpdate(event.data);
      case RealtimeEventType.roundReveal:
        _handleReveal(event.data);
      case RealtimeEventType.gameEnd:
        logger.i('[QuizCubit] game ended | scoreboard=${event.data['scoreboard']}');
        _timer?.cancel();
        emit(QuizGameEnded(
          scoreboard: List<Map<String, dynamic>>.from(
              event.data['scoreboard'] as List),
        ));
      default:
        break;
    }
  }

  void _handleNewQuestion(Map<String, dynamic> data) {
    _questionIndex++;
    _currentQuestion = ClientQuestion.fromJson(data);
    logger.i(
        '[QuizCubit] question:new received | questionId=${_currentQuestion!.id} '
        'choicesCount=${_currentQuestion!.choices.length} timerMs=300000');

    emit(QuizQuestion(
      question: _currentQuestion!,
      questionIndex: _questionIndex,
      totalQuestions: _totalQuestions,
      timeRemaining: _roundDuration,
    ));
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    var remaining = _roundDuration;
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
    final s = state;
    if (s is QuizQuestion) emit(s.copyWith(playerAnswers: answers));
  }

  void _handleReveal(Map<String, dynamic> data) {
    _timer?.cancel();
    final correctIndex = data['correctIndex'] as int;
    final raw = data['playerAnswers'] as Map<String, dynamic>? ?? {};
    final answers = raw.map((k, v) => MapEntry(k, v as int?));
    final scores = Map<String, int>.from(data['scores'] as Map);
    final myAnswer = _myPlayerId != null ? answers[_myPlayerId] : null;

    logger.i(
        '[QuizCubit] round:reveal received | correctIndex=$correctIndex '
        'myAnswer=$myAnswer isCorrect=${myAnswer == correctIndex} '
        'scoreGained=${myAnswer == correctIndex ? 10 : 0}');
    emit(QuizReveal(
      question: _currentQuestion!,
      correctIndex: correctIndex,
      playerAnswers: answers,
      scores: scores,
      myAnswer: myAnswer,
    ));
  }

  Future<void> submitAnswer(int answerIndex) async {
    final s = state;
    if (s is! QuizQuestion || _myPlayerId == null || _roomCode == null) return;
    logger.i(
        '[QuizCubit] answer submitted | questionId=${s.question.id} selectedIndex=$answerIndex');
    // Optimistic UI update — lock button immediately
    emit(s.copyWith(myAnswer: answerIndex));
    // Send to Node.js REST (server validates and scores)
    await apiService.submitAnswer(
        _roomCode!, _myPlayerId!, s.question.id, answerIndex);
  }

  @override
  Future<void> close() {
    _sub.cancel();
    _timer?.cancel();
    return super.close();
  }
}
