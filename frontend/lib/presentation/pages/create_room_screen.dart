import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/game_cubit/game_cubit.dart';
import '../cubits/game_cubit/game_state.dart';

class _Subject {
  final String key;
  final String displayName;
  final int questionCount;
  const _Subject(this.key, this.displayName, this.questionCount);
}

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  String? _selectedSubject;
  int _maxPlayers = 2;

  // These are the static options; the real question counts come from /api/subjects
  // but we show them hard-coded here to avoid a network call on this screen.
  // The server enforces the actual limits.
  static const _subjects = [
    _Subject('ukrainian_language', 'Українська мова та літ.', 1923),
    _Subject('history', 'Історія України', 1138),
    _Subject('geography', 'Географія', 476),
    _Subject('math', 'Математика', 58),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocListener<GameCubit, GameState>(
      listener: (ctx, state) {
        if (state is GameCreated) {
          context.go('/room/${state.roomCode}');
        } else if (state is GameError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Нова кімната'),
          leading: BackButton(onPressed: () => context.go('/')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Оберіть предмет',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  ..._subjects.map((s) => _SubjectTile(
                        subject: s,
                        selected: _selectedSubject == s.key,
                        onTap: () =>
                            setState(() => _selectedSubject = s.key),
                      )),
                  const SizedBox(height: 24),
                  Text(
                    'Кількість гравців',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      4,
                      (i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: _PlayerCountChip(
                          count: i + 1,
                          selected: _maxPlayers == i + 1,
                          onTap: () =>
                              setState(() => _maxPlayers = i + 1),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  BlocBuilder<GameCubit, GameState>(
                    builder: (ctx, state) {
                      final loading = state is GameCreating;
                      return FilledButton(
                        onPressed: _selectedSubject == null || loading
                            ? null
                            : () => ctx.read<GameCubit>().createRoom(
                                  _selectedSubject!,
                                  _maxPlayers,
                                ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Створити кімнату'),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  final _Subject subject;
  final bool selected;
  final VoidCallback onTap;

  const _SubjectTile({
    required this.subject,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                subject.displayName,
                style: TextStyle(
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Text(
              '${subject.questionCount} питань',
              style: TextStyle(
                color: cs.onSurface.withAlpha(150),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerCountChip extends StatelessWidget {
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _PlayerCountChip({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? cs.primary : Colors.white24,
          ),
        ),
        child: Center(
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
