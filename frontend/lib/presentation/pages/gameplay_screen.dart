import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';
import '../cubits/quiz_cubit/quiz_state.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/room_cubit/room_state.dart';
import '../widgets/timer_bar.dart';
import '../widgets/answer_button.dart';
import '../widgets/player_chip.dart';

class GameplayScreen extends StatelessWidget {
  final String roomCode;
  const GameplayScreen({super.key, required this.roomCode});

  @override
  Widget build(BuildContext context) {
    return BlocListener<QuizCubit, QuizState>(
      listener: (ctx, state) {
        if (state is QuizReveal) {
          ctx.go('/room/$roomCode/reveal');
        } else if (state is QuizGameEnded) {
          ctx.go('/room/$roomCode/results');
        }
      },
      child: Scaffold(
        body: BlocBuilder<QuizCubit, QuizState>(
          builder: (ctx, quizState) {
            if (quizState is QuizInitial) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Завантаження питання...'),
                  ],
                ),
              );
            }

            if (quizState is! QuizQuestion) {
              return const Center(child: CircularProgressIndicator());
            }

            return _GameplayBody(
              roomCode: roomCode,
              state: quizState,
            );
          },
        ),
      ),
    );
  }
}

class _GameplayBody extends StatelessWidget {
  final String roomCode;
  final QuizQuestion state;

  const _GameplayBody({required this.roomCode, required this.state});

  @override
  Widget build(BuildContext context) {
    final myPlayerId = context.read<RoomCubit>().myPlayerId;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Progress + timer
            Row(
              children: [
                Text(
                  'Питання ${state.questionIndex}/${state.totalQuestions}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
            TimerBar(remaining: state.timeRemaining),
            const SizedBox(height: 20),

            // Question text
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    state.question.text,
                    style: const TextStyle(fontSize: 18, height: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Answer choices
            ...List.generate(state.question.choices.length, (i) {
              final answerState = _answerState(i, state.myAnswer);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AnswerButton(
                  text: state.question.choices[i],
                  state: answerState,
                  onTap: state.myAnswer == null
                      ? () => context.read<QuizCubit>().submitAnswer(i)
                      : null,
                ),
              );
            }),
            const SizedBox(height: 12),

            // Player answer status chips
            BlocBuilder<RoomCubit, RoomState>(
              builder: (ctx, roomState) {
                if (roomState.players.isEmpty) return const SizedBox();
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: roomState.players.map((p) {
                    final hasAnswered =
                        state.playerAnswers.containsKey(p.id) &&
                            state.playerAnswers[p.id] != null;
                    return PlayerChip(
                      player: p,
                      hasAnswered: hasAnswered,
                      isMe: p.id == myPlayerId,
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  AnswerButtonState _answerState(int index, int? myAnswer) {
    if (myAnswer == null) return AnswerButtonState.idle;
    if (myAnswer == index) return AnswerButtonState.selected;
    return AnswerButtonState.idle;
  }
}
