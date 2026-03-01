import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum AnswerButtonState { idle, selected, correct, wrong }

class AnswerButton extends StatelessWidget {
  final String text;
  final AnswerButtonState state;
  final VoidCallback? onTap;

  const AnswerButton({
    super.key,
    required this.text,
    this.state = AnswerButtonState.idle,
    this.onTap,
  });

  Color _bgColor(BuildContext ctx) {
    return switch (state) {
      AnswerButtonState.correct => Colors.green.shade700,
      AnswerButtonState.wrong => Colors.red.shade700,
      AnswerButtonState.selected =>
        Theme.of(ctx).colorScheme.primary.withAlpha(153),
      AnswerButtonState.idle =>
        Theme.of(ctx).colorScheme.surfaceContainerHighest,
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: state == AnswerButtonState.idle ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _bgColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Text(
          text,
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    )
        .animate(target: state == AnswerButtonState.selected ? 1 : 0)
        .scaleXY(
          begin: 1.0,
          end: 0.97,
          duration: 150.ms,
          curve: Curves.easeIn,
        )
        .then()
        .scaleXY(
          begin: 0.97,
          end: 1.0,
          duration: 300.ms,
          curve: Curves.elasticOut,
        );
  }
}
