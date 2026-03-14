class LocationPing {
  final String? id;
  final String deviceId;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final String? gsmCellId;
  final String? networkProvider;
  final int? signalStrength;
  final DateTime recordedAt;

  const LocationPing({
    this.id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.gsmCellId,
    this.networkProvider,
    this.signalStrength,
    required this.recordedAt,
  });

  factory LocationPing.fromJson(Map<String, dynamic> json) {
    return LocationPing(
      id: json['id'] as String?,
      deviceId: json['device_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracyM:
          json['accuracy_m'] != null ? (json['accuracy_m'] as num).toDouble() : null,
      gsmCellId: json['gsm_cell_id'] as String?,
      networkProvider: json['network_provider'] as String?,
      signalStrength: json['signal_strength'] as int?,
      recordedAt: DateTime.parse(json['recorded_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'device_id': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (gsmCellId != null) 'gsm_cell_id': gsmCellId,
      if (networkProvider != null) 'network_provider': networkProvider,
      if (signalStrength != null) 'signal_strength': signalStrength,
      'recorded_at': recordedAt.toIso8601String(),
    };
  }
}
