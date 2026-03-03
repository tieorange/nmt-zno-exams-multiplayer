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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<RoomCubit>().myPlayerId == null) {
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<QuizCubit, QuizState>(
      // Navigate away when the next question arrives or the game ends
      listenWhen: (_, curr) => curr is QuizQuestion || curr is QuizGameEnded,
      listener: (ctx, state) {
        if (state is QuizQuestion) {
          ctx.go('/room/${widget.roomCode}/game');
        } else if (state is QuizGameEnded) {
          ctx.go('/room/${widget.roomCode}/results');
        }
      },
      builder: (ctx, state) {
        final rev = state is QuizReveal ? state : null;
        if (rev == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final isCorrect = rev.myAnswer == rev.correctIndex;

        return BlocBuilder<RoomCubit, RoomState>(
          builder: (_, roomState) {
            final isCreator = roomState.players
                .any((p) => p.id == context.read<RoomCubit>().myPlayerId && p.isCreator);

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
                              color: isCorrect
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  isCorrect ? '✅ Правильно!' : '❌ Помилка',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (isCorrect)
                                  Text(
                                    '+${rev.myScoreGained ?? 0} балів',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Colors.greenAccent,
                                    ),
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
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Answer buttons with reveal states
                      ...List.generate(rev.question.choices.length, (i) {
                        AnswerState answerState;
                        if (i == rev.correctIndex) {
                          answerState = AnswerState.correct;
                        } else if (i == rev.myAnswer &&
                            rev.myAnswer != rev.correctIndex) {
                          answerState = AnswerState.wrong;
                        } else {
                          answerState = AnswerState.idle;
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child:
                              AnswerButton(
                                    text: rev.question.choices[i],
                                    state: answerState,
                                  )
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Рахунок:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
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
                                      int.parse(
                                        p.color.replaceFirst('#', '0xFF'),
                                      ),
                                    ),
                                    child: Text(
                                      p.name[0],
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
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
                      const SizedBox(height: 16),
                      // Next question control
                      if (isCreator)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () =>
                                context.read<QuizCubit>().nextQuestion(),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text(
                              'Наступне питання',
                              style: TextStyle(fontSize: 16),
                            ),
                          )
                              .animate()
                              .fadeIn(
                                delay: const Duration(milliseconds: 500),
                                duration: const Duration(milliseconds: 300),
                              )
                              .slideY(begin: 0.3),
                        )
                      else
                        Center(
                          child: Text(
                            'Очікуємо творця кімнати…',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
