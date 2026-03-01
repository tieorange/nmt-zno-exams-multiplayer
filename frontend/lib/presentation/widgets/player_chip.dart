import 'package:flutter/material.dart';
import '../../data/models/player_model.dart';

class PlayerChip extends StatelessWidget {
  final PlayerModel player;
  final bool hasAnswered;
  final bool isMe;

  const PlayerChip({
    super.key,
    required this.player,
    this.hasAnswered = false,
    this.isMe = false,
  });

  Color get _color {
    try {
      return Color(int.parse(player.color.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.teal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withAlpha(38),
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
            radius: 12,
            backgroundColor: _color,
            child: Text(
              player.name.isNotEmpty ? player.name[0] : '?',
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${player.name}${isMe ? ' (ти)' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          if (hasAnswered) ...[
            const SizedBox(width: 4),
            const Icon(Icons.check_circle, size: 13, color: Colors.greenAccent),
          ],
        ],
      ),
    );
  }
}
