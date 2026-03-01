import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';
import '../cubits/quiz_cubit/quiz_state.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/room_cubit/room_state.dart';
import '../widgets/answer_button.dart';
import '../widgets/player_chip.dart';
import '../widgets/timer_bar.dart';

class GameplayScreen extends StatelessWidget {
  final String roomCode;
  const GameplayScreen({super.key, required this.roomCode});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<QuizCubit, QuizState>(
      listener: (ctx, state) {
        if (state is QuizReveal) {
          ctx.go('/room/$roomCode/reveal');
        } else if (state is QuizGameEnded) {
          ctx.go('/room/$roomCode/results');
        }
      },
      builder: (ctx, state) {
        final q = state is QuizQuestion ? state : null;
        if (q == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Progress & Timer
                  Row(
                    children: [
                      Text(
                        'Питання ${q.questionIndex}/${q.totalQuestions}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TimerBar(remaining: q.timeRemaining, total: q.totalTime),
                  const SizedBox(height: 20),
                  // Question card
                  Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          q.question.text,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                          ),
                        ),
                      )
                      .animate()
                      .fadeIn(duration: const Duration(milliseconds: 400))
                      .slideY(begin: -0.1),
                  const SizedBox(height: 20),
                  // Answer buttons
                  Expanded(
                    child: ListView.separated(
                      itemCount: q.question.choices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        AnswerState answerState = AnswerState.idle;
                        if (q.myAnswer != null) {
                          answerState = q.myAnswer == i ? AnswerState.selected : AnswerState.idle;
                        }
                        return AnswerButton(
                              text: q.question.choices[i],
                              state: answerState,
                              // Bug 11 fix: disable all buttons once player has answered
                              onTap: q.myAnswer == null
                                  ? () => ctx.read<QuizCubit>().submitAnswer(i)
                                  : null,
                            )
                            .animate()
                            .fadeIn(
                              delay: Duration(milliseconds: i * 80),
                              duration: const Duration(milliseconds: 300),
                            )
                            .slideX(begin: 0.15);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Player status chips
                  BlocBuilder<RoomCubit, RoomState>(
                    builder: (ctx, roomState) => Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: roomState.players
                          .map(
                            (p) => PlayerChip(
                              player: p,
                              hasAnswered:
                                  q.playerAnswers.containsKey(p.id) &&
                                  q.playerAnswers[p.id] != null,
                            ),
                          )
                          .toList(),
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
