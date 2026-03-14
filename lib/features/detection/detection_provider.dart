import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'detection_repository.dart';

final detectionRepositoryProvider = Provider<DetectionRepository>(
  (_) => DetectionRepository(),
);
