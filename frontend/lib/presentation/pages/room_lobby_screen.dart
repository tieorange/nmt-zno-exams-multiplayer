import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../cubits/room_cubit/room_cubit.dart';
import '../cubits/room_cubit/room_state.dart';
import '../cubits/quiz_cubit/quiz_cubit.dart';
import '../widgets/player_chip.dart';

const List<String> _nmtFacts = [
  'НМТ складається з трьох обов\'язкових предметів: Математика, Українська мова та Історія',
  'Тест з кожного предмету триває 150 хвилин і містить тестові завдання',
  'За правильну відповідь можна отримати від 1 до 3 балів залежно від складності',
  'НМТ замінив ЗНО у 2022 році як основний вступний іспит',
  'Результати НМТ дійсні впродовж 5 років для вступу до університету',
  'Географія є предметом за вибором і не є обов\'язковою для більшості спеціальностей',
];

class RoomLobbyScreen extends StatefulWidget {
  final String roomCode;
  const RoomLobbyScreen({super.key, required this.roomCode});

  @override
  State<RoomLobbyScreen> createState() => _RoomLobbyScreenState();
}

class _RoomLobbyScreenState extends State<RoomLobbyScreen> {
  Timer? _roomSyncTimer;
  bool _isCountingDown = false;
  int _countdownValue = 3;
  Timer? _countdownTimer;

  String get _joinUrl {
    final base = Uri.base;
    final portStr = base.hasPort ? ':${base.port}' : '';
    return '${base.scheme}://${base.host}$portStr/#/room/${widget.roomCode}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RoomCubit>().joinRoom(widget.roomCode);
    });

    // Fallback sync: if realtime events are missed, poll room state while waiting.
    _roomSyncTimer = Timer.periodic(const Duration(seconds: 1), (_) {
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
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _isCountingDown = true;
      _countdownValue = 3;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdownValue <= 1) {
        t.cancel();
        if (mounted) context.go('/room/${widget.roomCode}/game');
      } else {
        setState(() => _countdownValue--);
      }
    });
  }

  void _showShareSheet(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      useSafeArea: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Запросити гравців',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: QrImageView(
                data: _joinUrl,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'або скопіюйте посилання:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _joinUrl));
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Посилання скопійовано!'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                icon: const Icon(Icons.link, color: Color(0xFF4ECDC4)),
                label: const Text(
                  'Копіювати посилання',
                  style: TextStyle(color: Color(0xFF4ECDC4)),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF4ECDC4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RoomCubit, RoomState>(
      listenWhen: (prev, curr) =>
          prev.status != RoomStatus.playing &&
          curr.status == RoomStatus.playing,
      listener: (ctx, state) => _startCountdown(),
      builder: (ctx, state) {
        final lobbyContent = Container(
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
                        onPressed: () {
                          ctx.read<RoomCubit>().leaveRoom();
                          ctx.read<QuizCubit>().reset();
                          ctx.go('/');
                        },
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
                  // Room code + share
                  Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 20,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
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
                                IconButton(
                                  onPressed: () => _showShareSheet(ctx),
                                  icon: const Icon(
                                    Icons.share_outlined,
                                    color: Color(0xFF4ECDC4),
                                  ),
                                  tooltip: 'Поділитися',
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
                  // Player count row
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
                  // Player chips + fun fact — scrollable so many players don't overflow
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: state.players
                                .map(
                                  (p) => PlayerChip(player: p)
                                      .animate(key: ValueKey(p.id))
                                      .fadeIn(duration: 300.ms)
                                      .scale(begin: const Offset(0.7, 0.7))
                                      .then(delay: 200.ms)
                                      .shimmer(
                                        duration: 600.ms,
                                        color: const Color(0xFF4ECDC4),
                                      ),
                                )
                                .toList(),
                          ),
                          if (state.status == RoomStatus.waiting)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: _FunFactCard(),
                            ),
                        ],
                      ),
                    ),
                  ),
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
                          child: state.isStartingGame
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
        );

        return Scaffold(
          body: Stack(
            fit: StackFit.expand,
            children: [
              lobbyContent,
              if (_isCountingDown)
                IgnorePointer(
                  child: Container(
                    color: Colors.black87,
                    child: Center(
                      child:
                          Text(
                                '$_countdownValue',
                                style: const TextStyle(
                                  fontSize: 96,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF4ECDC4),
                                ),
                              )
                              .animate(key: ValueKey(_countdownValue))
                              .scale(
                                begin: const Offset(1.6, 1.6),
                                duration: 600.ms,
                                curve: Curves.easeOut,
                              )
                              .fadeIn(duration: 200.ms),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FunFactCard extends StatefulWidget {
  const _FunFactCard();

  @override
  State<_FunFactCard> createState() => _FunFactCardState();
}

class _FunFactCardState extends State<_FunFactCard> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _nmtFacts.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Text(
                _nmtFacts[_index],
                key: ValueKey(_index),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.55),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
