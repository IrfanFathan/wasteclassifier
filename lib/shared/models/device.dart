class Device {
  final String? id;
  final String deviceName;
  final String? gsmIccid;
  final String? firmwareVersion;
  final bool isActive;
  final DateTime registeredAt;
  final DateTime? lastSeenAt;

  const Device({
    this.id,
    required this.deviceName,
    this.gsmIccid,
    this.firmwareVersion,
    this.isActive = true,
    required this.registeredAt,
    this.lastSeenAt,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String?,
      deviceName: json['device_name'] as String,
      gsmIccid: json['gsm_iccid'] as String?,
      firmwareVersion: json['firmware_version'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      registeredAt: DateTime.parse(json['registered_at'] as String),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'device_name': deviceName,
      if (gsmIccid != null) 'gsm_iccid': gsmIccid,
      if (firmwareVersion != null) 'firmware_version': firmwareVersion,
      'is_active': isActive,
      'registered_at': registeredAt.toIso8601String(),
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt!.toIso8601String(),
    };
  }
}
