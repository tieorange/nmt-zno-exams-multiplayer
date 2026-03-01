import 'package:flutter/material.dart';
import '../../data/models/player_model.dart';

class PlayerChip extends StatelessWidget {
  final PlayerModel player;
  final bool hasAnswered;

  const PlayerChip({super.key, required this.player, this.hasAnswered = false});

  Color get _color => Color(int.parse(player.color.replaceFirst('#', '0xFF')));

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasAnswered ? _color : Colors.white24,
          width: hasAnswered ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _color,
            child: Text(player.name[0], style: const TextStyle(fontSize: 12, color: Colors.white)),
          ),
          const SizedBox(width: 6),
          Text(player.name, style: const TextStyle(fontSize: 13)),
          if (hasAnswered) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check_circle, size: 14, color: Colors.greenAccent),
          ],
        ],
      ),
    );
  }
}
