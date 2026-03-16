// Centralised constants for the detection pipeline.
//
// All tuneable thresholds and paths live here so they can be adjusted
// without hunting through multiple files.

const double kConfidenceThreshold = 0.40;
const double kNmsIouThreshold = 0.45;
const double kBlurSkipThreshold = 100.0;
const int kInputSize = 640;
const int kSmootherWindowSize = 5;
const int kMaxFpsMs = 66; // ~15 FPS
const double kSmootherMatchIou = 0.3;
const int kSmootherMinAppearances = 2;
