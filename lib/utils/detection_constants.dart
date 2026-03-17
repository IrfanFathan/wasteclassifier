// Centralised constants for the detection pipeline.
//
// All tuneable thresholds and paths live here so they can be adjusted
// without hunting through multiple files.
//
// Model type: Teachable Machine (image classification, NOT object detection).
// Input:  [1, 224, 224, 3] NHWC, float32, normalised to [0, 1].
// Output: [1, numClasses]  flat probability vector.

const double kConfidenceThreshold = 0.40;
const double kNmsIouThreshold = 0.45;
const double kBlurSkipThreshold = 100.0;
const int kInputSize = 224;
const int kSmootherWindowSize = 5;
const int kMaxFpsMs = 66; // ~15 FPS
const double kSmootherMatchIou = 0.3;
const int kSmootherMinAppearances = 2;
