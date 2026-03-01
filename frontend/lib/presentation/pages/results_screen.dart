import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  late final ConfettiController _confetti =
      ConfettiController(duration: const Duration(seconds: 5));

  @override
  void initState() {
    super.initState();
    _confetti.play();
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
        final scoreboard = state is QuizGameEnded ? state.scoreboard : [];
        final myPlayerId = ctx.read<RoomCubit>().myPlayerId;
        final isCreator = ctx.read<RoomCubit>().myIsCreator;
        final myRank = scoreboard.indexWhere(
                (e) => e['id'] == myPlayerId) +
            1;
        final isWinner = myRank == 1 && scoreboard.isNotEmpty;

        return Scaffold(
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          Text(
                            isWinner ? '🏆 Ви перемогли!' : 'Результати',
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isWinner
                                      ? const Color(0xFFFFEAA7)
                                      : Colors.white,
                                ),
                          )
                              .animate()
                              .fadeIn(duration: 600.ms)
                              .slideY(begin: -0.3, end: 0),
                          const SizedBox(height: 32),
                          Expanded(
                            child: scoreboard.isEmpty
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : ListView.builder(
                                    itemCount: scoreboard.length,
                                    itemBuilder: (_, i) {
                                      final entry = scoreboard[i]
                                          as Map<String, dynamic>;
                                      final rank =
                                          entry['rank'] as int? ?? i + 1;
                                      final name =
                                          entry['name'] as String? ?? '?';
                                      final score =
                                          entry['score'] as int? ?? 0;
                                      final color = entry['color'] as String? ??
                                          '#4ECDC4';
                                      final isMe = entry['id'] == myPlayerId;

                                      return _ScoreRow(
                                        rank: rank,
                                        name: name,
                                        score: score,
                                        color: color,
                                        isMe: isMe,
                                        index: i,
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 24),
                          if (isCreator) ...[
                            FilledButton.icon(
                              onPressed: () => context.go('/create'),
                              icon: const Icon(Icons.add),
                              label: const Text('Нова гра'),
                              style: FilledButton.styleFrom(
                                minimumSize:
                                    const Size.fromHeight(48),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          OutlinedButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.home),
                            label: const Text('На головну'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Confetti for winner
              if (isWinner)
                Align(
                  alignment: Alignment.topCenter,
                  child: ConfettiWidget(
                    confettiController: _confetti,
                    blastDirectionality: BlastDirectionality.explosive,
                    emissionFrequency: 0.05,
                    numberOfParticles: 25,
                    gravity: 0.1,
                    colors: const [
                      Color(0xFFFF6B6B),
                      Color(0xFF4ECDC4),
                      Color(0xFFFFEAA7),
                      Color(0xFFDDA0DD),
                      Color(0xFF96CEB4),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final int rank;
  final String name;
  final int score;
  final String color;
  final bool isMe;
  final int index;

  const _ScoreRow({
    required this.rank,
    required this.name,
    required this.score,
    required this.color,
    required this.isMe,
    required this.index,
  });

  Color get _parsedColor {
    try {
      return Color(int.parse(color.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rankEmoji = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '$rank.',
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe
            ? Theme.of(context).colorScheme.primaryContainer.withAlpha(80)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: isMe
            ? Border.all(
                color: Theme.of(context).colorScheme.primary, width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(rankEmoji,
                style: const TextStyle(fontSize: 20),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 18,
            backgroundColor: _parsedColor,
            child: Text(
              name.isNotEmpty ? name[0] : '?',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$name${isMe ? ' (ти)' : ''}',
              style: TextStyle(
                fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            '$score',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Color(0xFF4ECDC4),
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: 100 * index))
        .fadeIn(duration: 400.ms)
        .slideX(begin: 0.2, end: 0);
  }
}
