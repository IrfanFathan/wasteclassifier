class DetectionEvent {
  final String? id;
  final String deviceId;
  final String wasteClassId;
  final String? locationPingId;
  final double confidence;
  final int? imageWidth;
  final int? imageHeight;
  final String? imageUrl;
  final List<Map<String, dynamic>>? boundingBoxes;
  final bool isActioned;
  final DateTime detectedAt;

  const DetectionEvent({
    this.id,
    required this.deviceId,
    required this.wasteClassId,
    this.locationPingId,
    required this.confidence,
    this.imageWidth,
    this.imageHeight,
    this.imageUrl,
    this.boundingBoxes,
    this.isActioned = false,
    required this.detectedAt,
  });

  factory DetectionEvent.fromJson(Map<String, dynamic> json) {
    return DetectionEvent(
      id: json['id'] as String?,
      deviceId: json['device_id'] as String,
      wasteClassId: json['waste_class_id'] as String,
      locationPingId: json['location_ping_id'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      imageWidth: json['image_width'] as int?,
      imageHeight: json['image_height'] as int?,
      imageUrl: json['image_url'] as String?,
      boundingBoxes: json['bounding_boxes'] != null
          ? List<Map<String, dynamic>>.from(json['bounding_boxes'] as List)
          : null,
      isActioned: json['is_actioned'] as bool? ?? false,
      detectedAt: DateTime.parse(json['detected_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'device_id': deviceId,
      'waste_class_id': wasteClassId,
      if (locationPingId != null) 'location_ping_id': locationPingId,
      'confidence': confidence,
      if (imageWidth != null) 'image_width': imageWidth,
      if (imageHeight != null) 'image_height': imageHeight,
      if (imageUrl != null) 'image_url': imageUrl,
      if (boundingBoxes != null) 'bounding_boxes': boundingBoxes,
      'is_actioned': isActioned,
      'detected_at': detectedAt.toIso8601String(),
    };
  }
}
