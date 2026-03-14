class WasteDetection {
  final String? id;
  final String wasteType;
  final double? latitude;
  final double? longitude;
  final String locationSource;
  final DateTime detectedAt;
  final String? deviceId;

  const WasteDetection({
    this.id,
    required this.wasteType,
    this.latitude,
    this.longitude,
    required this.locationSource,
    required this.detectedAt,
    this.deviceId,
  });

  factory WasteDetection.fromJson(Map<String, dynamic> json) {
    return WasteDetection(
      id: json['id'] as String?,
      wasteType: json['waste_type'] as String,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      locationSource: json['location_source'] as String,
      detectedAt: DateTime.parse(json['detected_at'] as String),
      deviceId: json['device_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'waste_type': wasteType,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'location_source': locationSource,
      // If passing to Supabase, better to let Supabase handle default now()
      // But we can include it as ISO8601 string if not null
      'detected_at': detectedAt.toIso8601String(),
      if (deviceId != null) 'device_id': deviceId,
    };
  }
}
