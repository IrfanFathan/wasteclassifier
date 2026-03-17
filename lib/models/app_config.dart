import 'dart:convert';
import 'bin_category.dart';

class AppConfig {
  List<BinCategory> bins;
  double confidenceThreshold;
  List<String> nothingLabels;

  AppConfig({
    required this.bins,
    this.confidenceThreshold = 0.50,
    required this.nothingLabels,
  });

  factory AppConfig.empty() => AppConfig(bins: [], nothingLabels: []);

  Map<String, dynamic> toJson() => {
    'bins': bins.map((b) => b.toJson()).toList(),
    'confidenceThreshold': confidenceThreshold,
    'nothingLabels': nothingLabels,
  };

  factory AppConfig.fromJson(Map<String, dynamic> json) => AppConfig(
    bins: (json['bins'] as List)
        .map((b) => BinCategory.fromJson(b as Map<String, dynamic>))
        .toList(),
    confidenceThreshold: (json['confidenceThreshold'] as num).toDouble(),
    nothingLabels: List<String>.from(json['nothingLabels'] as List),
  );

  String toJsonString() => jsonEncode(toJson());

  factory AppConfig.fromJsonString(String jsonString) =>
      AppConfig.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
}
