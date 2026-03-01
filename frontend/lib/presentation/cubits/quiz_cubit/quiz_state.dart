import 'package:equatable/equatable.dart';
import '../../../data/models/question_model.dart';

abstract class QuizState extends Equatable {
  const QuizState();
}

class QuizInitial extends QuizState {
  const QuizInitial();
  @override
  List<Object?> get props => [];
}

class QuizQuestion extends QuizState {
  final ClientQuestion question;
  final int questionIndex;
  final int totalQuestions;
  final Duration timeRemaining;
  final int? myAnswer;
  final Map<String, int?> playerAnswers;

  const QuizQuestion({
    required this.question,
    required this.questionIndex,
    required this.totalQuestions,
    required this.timeRemaining,
    this.myAnswer,
    this.playerAnswers = const {},
  });

  QuizQuestion copyWith({
    Duration? timeRemaining,
    int? myAnswer,
    Map<String, int?>? playerAnswers,
  }) => QuizQuestion(
    question: question,
    questionIndex: questionIndex,
    totalQuestions: totalQuestions,
    timeRemaining: timeRemaining ?? this.timeRemaining,
    myAnswer: myAnswer ?? this.myAnswer,
    playerAnswers: playerAnswers ?? this.playerAnswers,
  );

  @override
  List<Object?> get props => [question, questionIndex, timeRemaining, myAnswer, playerAnswers];
}

class QuizReveal extends QuizState {
  final ClientQuestion question;
  final int correctIndex;
  final Map<String, int?> playerAnswers;
  final Map<String, int> scores;
  final int? myAnswer;

  const QuizReveal({
    required this.question,
    required this.correctIndex,
    required this.playerAnswers,
    required this.scores,
    this.myAnswer,
  });

  @override
  List<Object?> get props => [question, correctIndex, playerAnswers, scores, myAnswer];
}

class QuizGameEnded extends QuizState {
  final List<Map<String, dynamic>> scoreboard;
  const QuizGameEnded({required this.scoreboard});
  @override
  List<Object?> get props => [scoreboard];
}

class QuizError extends QuizState {
  final String message;
  const QuizError(this.message);
  @override
  List<Object?> get props => [message];
}
