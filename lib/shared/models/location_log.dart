class LocationLog {
  final String? id;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final String? deviceId;

  const LocationLog({
    this.id,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.deviceId,
  });

  factory LocationLog.fromJson(Map<String, dynamic> json) {
    return LocationLog(
      id: json['id'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      recordedAt: DateTime.parse(json['recorded_at'] as String),
      deviceId: json['device_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'recorded_at': recordedAt.toIso8601String(),
      if (deviceId != null) 'device_id': deviceId,
    };
  }
}
