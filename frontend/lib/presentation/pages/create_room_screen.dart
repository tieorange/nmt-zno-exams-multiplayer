import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/game_cubit/game_cubit.dart';
import '../cubits/game_cubit/game_state.dart';

// Subject key → display icon (fallback for subjects the backend doesn't annotate)
const _subjectIcons = <String, String>{
  'ukrainian_language': '🇺🇦',
  'history': '📜',
  'geography': '🗺️',
  'math': '📐',
};

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});
  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  String? _selectedSubject;
  int _maxPlayers = 2;

  @override
  void initState() {
    super.initState();
    // Load subjects from backend on screen entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameCubit>().loadSubjects();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GameCubit, GameState>(
      listener: (ctx, state) {
        if (state is GameCreated) {
          ctx.go('/room/${state.roomCode}');
        } else if (state is GameError) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Нова кімната'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Оберіть предмет',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              // Subject list — driven by backend response
              BlocBuilder<GameCubit, GameState>(
                buildWhen: (_, s) =>
                    s is GameSubjectsLoading ||
                    s is GameSubjectsLoaded ||
                    s is GameError,
                builder: (ctx, state) {
                  if (state is GameSubjectsLoading) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (state is GameError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            state.message,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                          TextButton(
                            onPressed: () =>
                                ctx.read<GameCubit>().loadSubjects(),
                            child: const Text('Спробувати знову'),
                          ),
                        ],
                      ),
                    );
                  }
                  final subjects = state is GameSubjectsLoaded
                      ? state.subjects
                      : const <Map<String, dynamic>>[];
                  return Column(
                    children: subjects.asMap().entries.map((entry) {
                      final i = entry.key;
                      final s = entry.value;
                      final key = s['key'] as String? ?? '';
                      final displayName = s['displayName'] as String? ?? key;
                      final questionCount = s['questionCount'] as int? ?? 0;
                      final enabled = s['enabled'] as bool? ?? true;
                      final icon = _subjectIcons[key] ?? '📚';
                      final selected = _selectedSubject == key;

                      return GestureDetector(
                        onTap: enabled
                            ? () => setState(() => _selectedSubject = key)
                            : null,
                        child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: !enabled
                                    ? const Color(0xFF0D1117)
                                    : selected
                                        ? const Color(
                                            0xFF4ECDC4,
                                          ).withValues(alpha: 0.2)
                                        : const Color(0xFF161B22),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF4ECDC4)
                                      : Colors.white12,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    icon,
                                    style: TextStyle(
                                      fontSize: 24,
                                      color: enabled ? null : Colors.white24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: enabled
                                                ? (selected
                                                    ? const Color(0xFF4ECDC4)
                                                    : Colors.white)
                                                : Colors.white24,
                                          ),
                                        ),
                                        Text(
                                          enabled
                                              ? '$questionCount питань'
                                              : 'Недоступно',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: enabled
                                                ? Colors.white38
                                                : Colors.white24,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF4ECDC4),
                                    ),
                                ],
                              ),
                            )
                            .animate()
                            .fadeIn(
                              delay: Duration(milliseconds: i * 80),
                              duration: const Duration(milliseconds: 300),
                            )
                            .slideX(begin: 0.2),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Кількість гравців',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: List.generate(4, (i) {
                  final n = i + 1;
                  final sel = _maxPlayers == n;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _maxPlayers = n),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                              : const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? const Color(0xFF4ECDC4)
                                : Colors.white12,
                            width: sel ? 2 : 1,
                          ),
                        ),
                        child: Text(
                          '$n',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: sel ? const Color(0xFF4ECDC4) : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const Spacer(),
              BlocBuilder<GameCubit, GameState>(
                builder: (ctx, state) {
                  final isLoading = state is GameCreating;
                  return SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selectedSubject == null || isLoading
                          ? null
                          : () {
                              ctx.read<GameCubit>().createRoom(
                                _selectedSubject!,
                                _maxPlayers,
                              );
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text(
                              'Створити кімнату',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
