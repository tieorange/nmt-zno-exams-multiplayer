import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';
import '../cubits/quiz_cubit/quiz_state.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/room_cubit/room_state.dart';
import '../widgets/answer_button.dart';

class RoundRevealScreen extends StatefulWidget {
  final String roomCode;
  const RoundRevealScreen({super.key, required this.roomCode});

  @override
  State<RoundRevealScreen> createState() => _RoundRevealScreenState();
}

class _RoundRevealScreenState extends State<RoundRevealScreen> {
  Timer? _autoAdvance;

  @override
  void initState() {
    super.initState();
    // Auto-advance after 4 seconds
    _autoAdvance = Timer(const Duration(seconds: 4), _advance);
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    super.dispose();
  }

  void _advance() {
    if (!mounted) return;
    final quizState = context.read<QuizCubit>().state;
    if (quizState is QuizGameEnded) {
      context.go('/room/${widget.roomCode}/results');
    } else {
      context.go('/room/${widget.roomCode}/game');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<QuizCubit, QuizState>(
      listener: (ctx, state) {
        // If a new question arrives, navigate immediately
        if (state is QuizQuestion) {
          _autoAdvance?.cancel();
          ctx.go('/room/${widget.roomCode}/game');
        } else if (state is QuizGameEnded) {
          _autoAdvance?.cancel();
          ctx.go('/room/${widget.roomCode}/results');
        }
      },
      builder: (ctx, state) {
        if (state is! QuizReveal) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final myPlayerId = ctx.read<RoomCubit>().myPlayerId;
        final isCorrect = state.myAnswer == state.correctIndex;

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Result header
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          isCorrect ? Icons.check_circle : Icons.cancel,
                          size: 64,
                          color: isCorrect
                              ? Colors.greenAccent
                              : Colors.redAccent,
                        )
                            .animate()
                            .scale(
                                begin: const Offset(0, 0),
                                end: const Offset(1, 1),
                                duration: 400.ms,
                                curve: Curves.elasticOut),
                        const SizedBox(height: 12),
                        Text(
                          isCorrect ? 'Правильно! +10' : 'Неправильно',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: isCorrect
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms)
                            .slideY(begin: 0.3, end: 0),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Question text
                  Text(
                    state.question.text,
                    style: const TextStyle(fontSize: 16, height: 1.4),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  // Answer choices with highlights
                  ...List.generate(state.question.choices.length, (i) {
                    AnswerButtonState btnState;
                    if (i == state.correctIndex) {
                      btnState = AnswerButtonState.correct;
                    } else if (i == state.myAnswer &&
                        state.myAnswer != state.correctIndex) {
                      btnState = AnswerButtonState.wrong;
                    } else {
                      btnState = AnswerButtonState.idle;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AnswerButton(
                        text: state.question.choices[i],
                        state: btnState,
                      ),
                    );
                  }),
                  const SizedBox(height: 16),

                  // Scoreboard
                  BlocBuilder<RoomCubit, RoomState>(
                    builder: (ctx, roomState) {
                      if (roomState.players.isEmpty) return const SizedBox();
                      final sorted = [...roomState.players]
                        ..sort((a, b) =>
                            (state.scores[b.id] ?? b.score)
                                .compareTo(state.scores[a.id] ?? a.score));
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Рахунок',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          ...sorted.map((p) {
                            final score = state.scores[p.id] ?? p.score;
                            final color = _parseColor(p.color);
                            final isMe = p.id == myPlayerId;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: color,
                                    child: Text(
                                      p.name.isNotEmpty ? p.name[0] : '?',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${p.name}${isMe ? ' (ти)' : ''}',
                                      style: TextStyle(
                                        fontWeight: isMe
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '$score',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Color(0xFF4ECDC4)),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      );
                    },
                  ),

                  const Spacer(),
                  const Text(
                    'Наступне питання через кілька секунд...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.teal;
    }
  }
}
