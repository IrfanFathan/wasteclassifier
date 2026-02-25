
class BinCategory {
  String id;
  String name;
  String emoji;
  int colorHex;
  List<String> mappedLabels;

  BinCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.colorHex,
    required this.mappedLabels,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'colorHex': colorHex,
        'mappedLabels': mappedLabels,
      };

  factory BinCategory.fromJson(Map<String, dynamic> json) => BinCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        colorHex: json['colorHex'] as int,
        mappedLabels: List<String>.from(json['mappedLabels'] as List),
      );

  BinCategory copyWith({
    String? id,
    String? name,
    String? emoji,
    int? colorHex,
    List<String>? mappedLabels,
  }) {
    return BinCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      colorHex: colorHex ?? this.colorHex,
      mappedLabels: mappedLabels ?? List.from(this.mappedLabels),
    );
  }
}
