import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  @override
  void initState() {
    super.initState();
    // Bug 9 fix: always navigate back to game screen after reveal.
    // GameplayScreen's BlocConsumer already handles QuizGameEnded → /results.
    // Having both screens try to push /results caused a double-navigation race.
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      context.go('/room/${widget.roomCode}/game');
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuizCubit, QuizState>(
      builder: (ctx, state) {
        final rev = state is QuizReveal ? state : null;
        if (rev == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final isCorrect = rev.myAnswer == rev.correctIndex;

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Result banner
                  Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isCorrect ? Colors.green.shade900 : Colors.red.shade900,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Text(
                              isCorrect ? '✅ Правильно!' : '❌ Помилка',
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                            ),
                            if (isCorrect)
                              const Text(
                                '+10 балів',
                                style: TextStyle(fontSize: 18, color: Colors.greenAccent),
                              ),
                          ],
                        ),
                      )
                      .animate()
                      .fadeIn(duration: const Duration(milliseconds: 400))
                      .scale(begin: const Offset(0.8, 0.8)),
                  const SizedBox(height: 20),
                  // Question recap
                  Text(
                    rev.question.text,
                    style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  // Answer buttons with reveal states
                  ...List.generate(rev.question.choices.length, (i) {
                    AnswerState answerState;
                    if (i == rev.correctIndex) {
                      answerState = AnswerState.correct;
                    } else if (i == rev.myAnswer && rev.myAnswer != rev.correctIndex) {
                      answerState = AnswerState.wrong;
                    } else {
                      answerState = AnswerState.idle;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AnswerButton(text: rev.question.choices[i], state: answerState)
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: i * 100),
                            duration: const Duration(milliseconds: 300),
                          )
                          .slideX(begin: 0.1),
                    );
                  }),
                  const Spacer(),
                  // Player scores
                  BlocBuilder<RoomCubit, RoomState>(
                    builder: (_, roomState) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Рахунок:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        ...roomState.players.map((p) {
                          final score = rev.scores[p.id] ?? p.score;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Color(
                                    int.parse(p.color.replaceFirst('#', '0xFF')),
                                  ),
                                  child: Text(
                                    p.name[0],
                                    style: const TextStyle(fontSize: 10, color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(p.name),
                                const Spacer(),
                                Text(
                                  '$score балів',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4ECDC4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'Наступне питання через 3 секунди…',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
