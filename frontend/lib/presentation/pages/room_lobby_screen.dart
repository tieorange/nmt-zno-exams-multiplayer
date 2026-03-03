import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/room_cubit/room_state.dart';
import '../widgets/player_chip.dart';

class RoomLobbyScreen extends StatefulWidget {
  final String roomCode;
  const RoomLobbyScreen({super.key, required this.roomCode});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  Timer? _roomSyncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomCubit>().joinRoom(widget.roomCode);
    });

    // Fallback sync: if realtime events are missed, poll room state while waiting.
    _roomSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final cubit = context.read<RoomCubit>();
      if (cubit.state.status == RoomStatus.waiting) {
        unawaited(cubit.syncRoomState());
      }
    });
  }

  @override
  void dispose() {
    _roomSyncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoomCubit, RoomState>(
      listener: (ctx, state) {
        if (state.status == RoomStatus.playing) {
          ctx.go('/room/${widget.roomCode}/game');
        }
      },
      builder: (ctx, state) {
        return Scaffold(
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
                    // Header
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => ctx.go('/'),
                          icon: const Icon(Icons.arrow_back_ios_new),
                        ),
                        const Expanded(
                          child: Text(
                            'Кімната очікування',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 32),
                    // Room code
                    Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF4ECDC4,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(
                                0xFF4ECDC4,
                              ).withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                'Код кімнати',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.roomCode,
                                    style: const TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF4ECDC4),
                                      letterSpacing: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    onPressed: () {
                                      Clipboard.setData(
                                        ClipboardData(text: widget.roomCode),
                                      );
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text('Код скопійовано!'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.copy,
                                      color: Color(0xFF4ECDC4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .scale(begin: const Offset(0.9, 0.9)),
                    const SizedBox(height: 32),
                    // Player count
                    Row(
                      children: [
                        Text(
                          'Гравці (${state.players.length}/${state.maxPlayers})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (state.status == RoomStatus.waiting)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.5),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.orange,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Очікування',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          state.players
                              .map(
                                (p) => PlayerChip(player: p)
                                    .animate()
                                    .fadeIn(duration: 300.ms)
                                    .scale(begin: const Offset(0.7, 0.7)),
                              )
                              .toList(),
                    ),
                    const Spacer(),
                    if (state.status == RoomStatus.error)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          state.errorMessage ?? 'Сталася помилка',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    // Start button (creator only)
                    BlocBuilder<RoomCubit, RoomState>(
                      builder: (ctx, _) {
                        final cubit = ctx.read<RoomCubit>();
                        if (!cubit.myIsCreator) {
                          return const Text(
                            'Очікуємо, поки творець почне гру…',
                            style: TextStyle(color: Colors.white54),
                            textAlign: TextAlign.center,
                          );
                        }
                        return SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed:
                                state.isStartingGame ||
                                        state.status != RoomStatus.waiting
                                    ? null
                                    : () => cubit.startGame(),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF4ECDC4),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child:
                                state.isStartingGame
                                    ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.black,
                                      ),
                                    )
                                    : const Text(
                                      'Почати гру 🚀',
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
          ),
        );
      },
    );
  }
}
