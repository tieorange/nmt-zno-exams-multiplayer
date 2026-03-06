import 'package:flutter/material.dart';

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

    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        color: color,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
