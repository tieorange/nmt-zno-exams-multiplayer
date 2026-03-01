import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

class TimerBar extends StatelessWidget {
  final Duration remaining;
  static const _total = Duration(minutes: 5);

  const TimerBar({super.key, required this.remaining});

  double get _percent =>
      (remaining.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);

  Color get _color {
    if (_percent > 0.5) return Colors.greenAccent;
    if (_percent > 0.25) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final secs = remaining.inSeconds.clamp(0, _total.inSeconds);
    final label = secs >= 60
        ? '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}'
        : '${secs}с'; // ignore: unnecessary_brace_in_string_interps

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearPercentIndicator(
          percent: _percent,
          lineHeight: 8,
          animation: true,
          animationDuration: 800,
          progressColor: _color,
          backgroundColor: Colors.grey.shade800,
          barRadius: const Radius.circular(4),
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              fontSize: 14, color: _color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
