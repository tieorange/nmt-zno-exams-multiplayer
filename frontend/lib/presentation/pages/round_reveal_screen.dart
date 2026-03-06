import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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
        return;
      }
      // Start polling fallback: detects missed question:new when creator presses
      // "Next Question" and Supabase Realtime doesn't deliver the event (e.g. LAN).
      // _pollRoundState handles QuizReveal state by calling _pollForNextQuestion.
      context.read<QuizCubit>().startPolling();
    });
  }

  void _explainWithAI(BuildContext context, QuizReveal rev, String aiType) {
    final correctChoice = rev.question.choices[rev.correctIndex];
    final choicesList = rev.question.choices
        .asMap()
        .entries
        .map((e) => '${String.fromCharCode(65 + e.key)}) ${e.value}')
        .join('\n');

    final prompt =
        'Поясни, будь ласка, чому правильна відповідь на це питання НМТ — саме та, що вказана.\n\n'
        'Питання: ${rev.question.text}\n\n'
        'Варіанти відповідей:\n$choicesList\n\n'
        'Правильна відповідь: ${String.fromCharCode(65 + rev.correctIndex)}) $correctChoice\n\n'
        'Поясни детально чому ця відповідь правильна і чому інші варіанти неправільні. '
        'Відповідай українською мовою.';

    final Uri url;
    String snackText = 'Промпт скопійовано — вставте в чат';
    if (aiType == 'gpt') {
      url = Uri.parse('https://chatgpt.com');
    } else if (aiType == 'gemini') {
      url = Uri.parse('https://gemini.google.com');
    } else {
      // Perplexity supports ?q= natively — prompt is auto-submitted.
      url = Uri(
        scheme: 'https',
        host: 'www.perplexity.ai',
        queryParameters: {'q': prompt},
      );
      snackText = 'Відкриваємо Perplexity…';
    }

    // Launch URL first — before any await — so iOS Safari's user-gesture chain
    // is intact when window.open() fires. Any await before launchUrl breaks it.
    unawaited(launchUrl(url, mode: LaunchMode.externalApplication));
    if (aiType != 'perplexity') {
      unawaited(Clipboard.setData(ClipboardData(text: prompt)));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snackText), duration: const Duration(seconds: 3)),
    );
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final isCorrect = rev.myAnswer == rev.correctIndex;

        return BlocBuilder<RoomCubit, RoomState>(
          builder: (_, roomState) {
            final isCreator = roomState.players.any(
              (p) => p.id == context.read<RoomCubit>().myPlayerId && p.isCreator,
            );

            String answerLabel(int? index) => index != null ? String.fromCharCode(65 + index) : '—';

            Color answerBadgeColor(int? index) {
              if (index == null) return Colors.grey.shade700;
              return index == rev.correctIndex ? Colors.green.shade700 : Colors.red.shade700;
            }

            return Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
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
                        const SizedBox(height: 16),
                        // Next question control
                        if (isCreator)
                          SizedBox(
                            width: double.infinity,
                            child:
                                FilledButton.icon(
                                      onPressed: () => context.read<QuizCubit>().nextQuestion(),
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
                        const SizedBox(height: 16),
                        // AI explanation buttons
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _explainWithAI(context, rev, 'gpt'),
                                icon: const Text('🤖', style: TextStyle(fontSize: 16)),
                                label: const Text('Пояснити з ChatGPT'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF10A37F),
                                  side: const BorderSide(color: Color(0xFF10A37F)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _explainWithAI(context, rev, 'gemini'),
                                icon: const Text('✨', style: TextStyle(fontSize: 16)),
                                label: const Text('Пояснити з Gemini'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF4285F4),
                                  side: const BorderSide(color: Color(0xFF4285F4)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _explainWithAI(context, rev, 'perplexity'),
                                icon: const Text('🔍', style: TextStyle(fontSize: 16)),
                                label: const Text('Пояснити з Perplexity'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF20B8CD),
                                  side: const BorderSide(color: Color(0xFF20B8CD)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ).animate().fadeIn(
                          delay: const Duration(milliseconds: 300),
                          duration: const Duration(milliseconds: 400),
                        ),
                        const SizedBox(height: 20),
                        // Player scores
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Рахунок:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            ...roomState.players.map((p) {
                              final score = rev.scores[p.id] ?? p.score;
                              final playerAnswer = rev.playerAnswers[p.id];
                              final isMe = p.id == context.read<RoomCubit>().myPlayerId;
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
                                        p.name.isNotEmpty ? p.name[0] : '?',
                                        style: const TextStyle(fontSize: 10, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        isMe ? '${p.name} (Ви)' : p.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        color: answerBadgeColor(playerAnswer),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          answerLabel(playerAnswer),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
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
                      ],
                    ),
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
