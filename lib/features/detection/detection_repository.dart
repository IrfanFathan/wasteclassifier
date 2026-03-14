import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/constants.dart';
import '../location/location_repository.dart';

class DetectionRepository {
  /// Saves a detection event to Supabase:
  ///   1. Compress and upload the JPEG snapshot to Storage.
  ///   2. Resolve `waste_class_id` from the label name.
  ///   3. Link to the most recent location ping.
  ///   4. Insert a row in `detection_events`.
  ///
  /// [rgbFrame] — the decoded RGB image at original resolution.
  /// [label]    — raw TFLite label string (must match `waste_classes.label`).
  /// [confidence] — raw softmax / sigmoid score in [0, 1].
  /// [cx], [cy] — pixel centre of the detected zone in the original frame.
  static Future<void> saveDetection({
    required String deviceId,
    required img.Image rgbFrame,
    required String label,
    required double confidence,
    required int cx,
    required int cy,
    required int frameWidth,
    required int frameHeight,
  }) async {
    final supabase = Supabase.instance.client;

    // 1. Encode JPEG at quality 70.
    final jpegBytes = img.encodeJpg(rgbFrame, quality: 70);

    // 2. Upload to Storage (private bucket).
    final path = '$deviceId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await supabase.storage
          .from(AppConstants.storageBucketDetections)
          .uploadBinary(
            path,
            jpegBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
    } catch (e) {
      debugPrint('DetectionRepository: image upload failed: $e');
    }

    // 3. Get signed URL (valid for 1 hour; update expiry as needed).
    String? imageUrl;
    try {
      imageUrl = await supabase.storage
          .from(AppConstants.storageBucketDetections)
          .createSignedUrl(path, 3600);
    } catch (e) {
      debugPrint('DetectionRepository: signed URL failed: $e');
    }

    // 4. Resolve waste_class_id.
    String? wasteClassId;
    try {
      final classRow = await supabase
          .from(AppConstants.tableWasteClasses)
          .select('id')
          .eq('label', label)
          .maybeSingle();
      wasteClassId = classRow?['id'] as String?;
    } catch (e) {
      debugPrint('DetectionRepository: waste class lookup failed: $e');
    }

    if (wasteClassId == null) {
      debugPrint(
        'DetectionRepository: label "$label" not found in waste_classes — skipping insert',
      );
      return;
    }

    // 5. Link to latest location ping (within last 3 minutes).
    final pingId = await LocationRepository.latestPingId(deviceId);

    // 6. Approximate bounding box from zone centre (zone is ~⅓ of frame).
    const zoneFraction = 0.33;
    final zoneW = (frameWidth * zoneFraction).round();
    final zoneH = (frameHeight * zoneFraction).round();
    final boxX = (cx - zoneW ~/ 2).clamp(0, frameWidth);
    final boxY = (cy - zoneH ~/ 2).clamp(0, frameHeight);

    final boundingBoxes = [
      {
        'x': boxX,
        'y': boxY,
        'w': zoneW,
        'h': zoneH,
        'label': label,
        'confidence': confidence,
      }
    ];

    // 7. Insert detection event.
    try {
      await supabase.from(AppConstants.tableDetectionEvents).insert({
        'device_id': deviceId,
        'waste_class_id': wasteClassId,
        'location_ping_id': ?pingId,
        'confidence': confidence,
        'image_width': frameWidth,
        'image_height': frameHeight,
        'image_url': ?imageUrl,
        'bounding_boxes': boundingBoxes,
      });
      debugPrint('DetectionRepository: detection_event inserted for label=$label');
    } catch (e) {
      debugPrint('DetectionRepository: insert failed: $e');
    }
  }
}
