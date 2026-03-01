import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/room_cubit/room_state.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';

class RoomLobbyScreen extends StatefulWidget {
  final String roomCode;
  const RoomLobbyScreen({super.key, required this.roomCode});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    // Auto-join on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_joining) {
        _joining = true;
        context.read<RoomCubit>().joinRoom(widget.roomCode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoomCubit, RoomState>(
      listener: (ctx, state) {
        if (state.status == RoomStatus.playing) {
          // Forward player context to QuizCubit before navigating
          final cubit = ctx.read<RoomCubit>();
          if (cubit.myPlayerId != null) {
            ctx
                .read<QuizCubit>()
                .setContext(cubit.myPlayerId!, state.code);
          }
          ctx.go('/room/${state.code}/game');
        }
      },
      builder: (ctx, state) {
        if (state.status == RoomStatus.initial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state.status == RoomStatus.error) {
          return Scaffold(
            appBar: AppBar(
              leading: BackButton(onPressed: () => context.go('/')),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text(
                    state.errorMessage ?? 'Помилка з\'єднання',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/'),
                    child: const Text('На головну'),
                  ),
                ],
              ),
            ),
          );
        }

        final cubit = ctx.read<RoomCubit>();
        final isCreator = cubit.myIsCreator;
        final canStart = isCreator && state.players.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: Text('Кімната ${state.code}'),
            leading: BackButton(onPressed: () => context.go('/')),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Поділитися посиланням',
                onPressed: () {
                  final url =
                      '${Uri.base.origin}/room/${state.code}';
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Посилання скопійовано!')),
                  );
                },
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Room code display
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Код кімнати',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.white54),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.code,
                            style: Theme.of(context)
                                .textTheme
                                .displayMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF4ECDC4),
                                  letterSpacing: 8,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Предмет: ${_subjectLabel(state.subject)}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Players list
                    Text(
                      'Гравці (${state.players.length}/${state.maxPlayers})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: state.players.isEmpty
                          ? const Center(
                              child: Text(
                              'Очікування гравців...',
                              style: TextStyle(color: Colors.white38),
                            ))
                          : ListView.builder(
                              itemCount: state.players.length,
                              itemBuilder: (_, i) {
                                final p = state.players[i];
                                final color = _parseColor(p.color);
                                final isMe = p.id == cubit.myPlayerId;
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: color,
                                    child: Text(
                                      p.name.isNotEmpty
                                          ? p.name[0]
                                          : '?',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(
                                    '${p.name}${isMe ? ' (ти)' : ''}',
                                    style: TextStyle(
                                      fontWeight: isMe
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  trailing: p.isCreator
                                      ? const Chip(
                                          label: Text('Організатор',
                                              style: TextStyle(fontSize: 11)),
                                          padding: EdgeInsets.zero,
                                          visualDensity:
                                              VisualDensity.compact,
                                        )
                                      : null,
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (isCreator)
                      FilledButton(
                        onPressed: canStart
                            ? () => ctx.read<RoomCubit>().startGame()
                            : null,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Почати гру'),
                      )
                    else
                      const Text(
                        'Очікуємо, доки організатор почне гру...',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _subjectLabel(String key) {
    return switch (key) {
      'ukrainian_language' => 'Українська мова',
      'history' => 'Історія України',
      'geography' => 'Географія',
      'math' => 'Математика',
      _ => key,
    };
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.teal;
    }
  }
}
