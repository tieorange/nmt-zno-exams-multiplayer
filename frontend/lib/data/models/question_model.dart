class ClientQuestion {
  final String id;
  final String subject;
  final String text;
  final List<String> choices;

  const ClientQuestion({
    required this.id,
    required this.subject,
    required this.text,
    required this.choices,
  });

  factory ClientQuestion.fromJson(Map<String, dynamic> json) => ClientQuestion(
        id: json['id'] as String,
        subject: json['subject'] as String,
        text: json['text'] as String,
        choices: List<String>.from(json['choices'] as List),
      );
}
