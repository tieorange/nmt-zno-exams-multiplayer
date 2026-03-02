import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class TimerBar extends StatelessWidget {
  final Duration remaining;
  final Duration total;

  const TimerBar({super.key, required this.remaining, required this.total});

  double get percent =>
      (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

  Color get color {
    if (percent > 0.5) return Colors.greenAccent;
    if (percent > 0.25) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final secs = remaining.inSeconds;
    final label = secs >= 60
        ? '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}'
        : '$secsс';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearPercentIndicator(
          percent: percent,
          lineHeight: 8,
          animation: true,
          animationDuration: 800,
          progressColor: color,
          backgroundColor: Colors.grey.shade800,
          barRadius: const Radius.circular(4),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
