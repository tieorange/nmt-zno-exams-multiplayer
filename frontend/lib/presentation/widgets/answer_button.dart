import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum AnswerState { idle, selected, correct, wrong }

class AnswerButton extends StatelessWidget {
  final String text;
  final AnswerState state;
  final VoidCallback? onTap;

  const AnswerButton({
    super.key,
    required this.text,
    this.state = AnswerState.idle,
    this.onTap,
  });

  Color _bgColor(BuildContext ctx) {
    return switch (state) {
      AnswerState.correct => Colors.green.shade700,
      AnswerState.wrong => Colors.red.shade700,
      AnswerState.selected => Theme.of(
        ctx,
      ).colorScheme.primary.withValues(alpha: 0.6),
      AnswerState.idle => Theme.of(ctx).colorScheme.surfaceContainerHighest,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
          onTap: state == AnswerState.idle ? onTap : null,
          child: AnimatedContainer(
            duration: 300.ms,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: _bgColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Text(
              text,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        )
        .animate(target: state == AnswerState.selected ? 1 : 0)
        .scaleXY(begin: 1.0, end: 0.97, duration: 150.ms, curve: Curves.easeIn)
        .then()
        .scaleXY(
          begin: 0.97,
          end: 1.0,
          duration: 300.ms,
          curve: Curves.elasticOut,
        );
  }
}
