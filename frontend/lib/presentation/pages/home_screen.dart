import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  void _showJoinDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Приєднатися до кімнати'),
        content: TextField(
          controller: _codeController,
          autofocus: true,
          maxLength: 3,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Введіть код кімнати (напр. A9X)',
            counterText: '',
          ),
          onSubmitted: (_) => _joinRoom(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => _joinRoom(ctx),
            child: const Text('Приєднатися'),
          ),
        ],
      ),
    );
  }

  void _joinRoom(BuildContext ctx) {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length == 3) {
      _codeController.clear();
      Navigator.of(ctx).pop();
      context.go('/room/$code');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.school, size: 80, color: Color(0xFF4ECDC4)),
                const SizedBox(height: 24),
                Text(
                  'НМТ Квіз',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4ECDC4),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Готуйся до НМТ разом з друзями',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white54,
                      ),
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: () => context.go('/create'),
                  icon: const Icon(Icons.add),
                  label: const Text('Створити кімнату'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _showJoinDialog,
                  icon: const Icon(Icons.login),
                  label: const Text('Приєднатися'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
