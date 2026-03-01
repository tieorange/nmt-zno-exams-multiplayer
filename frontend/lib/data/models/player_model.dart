class PlayerModel {
  final String id;
  final String name;
  final String color;
  final int score;
  final bool isCreator;

  const PlayerModel({
    required this.id,
    required this.name,
    required this.color,
    required this.score,
    required this.isCreator,
  });

  factory PlayerModel.fromJson(Map<String, dynamic> json) => PlayerModel(
    id: json['id'] as String,
    name: json['name'] as String,
    color: json['color'] as String,
    score: json['score'] as int? ?? 0,
    isCreator: json['isCreator'] as bool? ?? false,
  );
}
