import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';
import '../cubits/quiz_cubit/quiz_state.dart';
import '../cubits/room_cubit/room_cubit.dart';

class ResultsScreen extends StatefulWidget {
  final String roomCode;
  const ResultsScreen({super.key, required this.roomCode});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ConfettiController _confetti = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    // Bug 10 fix: play confetti only if the current player won
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final roomCubit = context.read<RoomCubit>();
      final quizState = context.read<QuizCubit>().state;
      if (quizState is QuizGameEnded && quizState.scoreboard.isNotEmpty) {
        final winner = quizState.scoreboard.first;
        if (winner['id'] == roomCubit.myPlayerId) {
          _confetti.play();
        }
      }
    });
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QuizCubit, QuizState>(
      builder: (ctx, state) {
        final scoreboard = state is QuizGameEnded
            ? state.scoreboard
            : const <Map<String, dynamic>>[];
        final isCreator = ctx.read<RoomCubit>().myIsCreator;

        return Stack(
          children: [
            Scaffold(
              body: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF0D2137), Color(0xFF0D1117)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        const Text(
                              '🏆 Підсумки',
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                            )
                            .animate()
                            .fadeIn(duration: const Duration(milliseconds: 600))
                            .scale(begin: const Offset(0.8, 0.8)),
                        const SizedBox(height: 32),
                        // Scoreboard
                        Expanded(
                          child: ListView.builder(
                            itemCount: scoreboard.length,
                            itemBuilder: (_, i) {
                              final entry = scoreboard[i];
                              final rank = entry['rank'] as int? ?? i + 1;
                              final name = entry['name'] as String? ?? '—';
                              final score = entry['score'] as int? ?? 0;
                              final color = entry['color'] as String? ?? '#4ECDC4';
                              final playerColor = Color(int.parse(color.replaceFirst('#', '0xFF')));
                              final medals = ['🥇', '🥈', '🥉'];
                              final medal = rank <= 3 ? medals[rank - 1] : '$rank.';

                              return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      color: rank == 1
                                          ? const Color(0xFFFFD700).withValues(alpha: 0.15)
                                          : const Color(0xFF161B22),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: rank == 1
                                            ? const Color(0xFFFFD700).withValues(alpha: 0.5)
                                            : Colors.white12,
                                        width: rank == 1 ? 2 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(medal, style: const TextStyle(fontSize: 24)),
                                        const SizedBox(width: 12),
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: playerColor,
                                          child: Text(
                                            name[0],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '$score балів',
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF4ECDC4),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .animate()
                                  .fadeIn(
                                    delay: Duration(milliseconds: i * 100),
                                    duration: const Duration(milliseconds: 400),
                                  )
                                  .slideX(begin: 0.2);
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                        if (isCreator)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => ctx.go('/create'),
                              icon: const Icon(Icons.refresh),
                              label: const Text(
                                'Нова тема',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF4ECDC4),
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => ctx.go('/'),
                              icon: const Icon(Icons.login_rounded),
                              label: const Text(
                                'Приєднатися до кімнати',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFF4ECDC4), width: 1.5),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Confetti
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confetti,
                blastDirection: 1.5708,
                emissionFrequency: 0.05,
                numberOfParticles: 30,
                gravity: 0.1,
                colors: const [
                  Color(0xFFFF6B6B),
                  Color(0xFF4ECDC4),
                  Color(0xFFFFEAA7),
                  Color(0xFFDDA0DD),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
