# TrashSense -- Complete Project Documentation

> **Package:** `com.example.wasteclassifier`
> **Version:** 1.0.0+1
> **Platform:** Android
> **Branch:** `detection-improvement`
> **Last updated:** March 2026

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technology Stack](#2-technology-stack)
3. [System Architecture](#3-system-architecture)
4. [App Flow (User Journey)](#4-app-flow-user-journey)
5. [Directory Structure](#5-directory-structure)
6. [Screens](#6-screens)
7. [Inference Pipeline](#7-inference-pipeline)
8. [Preprocessing: Dual Path](#8-preprocessing-dual-path)
9. [Teachable Machine Model Specification](#9-teachable-machine-model-specification)
10. [8x8 Grid Mapping System](#10-8x8-grid-mapping-system)
11. [ESP32 Communication Protocol](#11-esp32-communication-protocol)
12. [Robot Navigation (WasteLocator)](#12-robot-navigation-wastelocator)
13. [Detection Overlay (UI)](#13-detection-overlay-ui)
14. [Native C++ / OpenCV Integration](#14-native-c--opencv-integration)
15. [Background Services](#15-background-services)
16. [Configuration and Persistence](#16-configuration-and-persistence)
17. [Dependencies](#17-dependencies)
18. [Test Suite](#18-test-suite)
19. [Build and Run Instructions](#19-build-and-run-instructions)
20. [Git History and Branches](#20-git-history-and-branches)
21. [Known Issues and Legacy Code](#21-known-issues-and-legacy-code)

---

## 1. Project Overview

TrashSense is a **Flutter Android application** that performs **real-time waste classification** using the phone's camera and a user-uploaded TFLite model exported from Google Teachable Machine. The app is designed to be mounted on a robotic waste-sorting system:

1. The phone camera captures live video of waste items on a conveyor or surface.
2. Each frame is preprocessed (resized to 224x224, normalised) and classified by a TFLite model.
3. The classification result is mapped to an **8x8 center-origin Cartesian grid** for spatial reference.
4. Classification data and **pick-and-place commands** are transmitted over WiFi to an **ESP32 microcontroller** that drives a robotic arm.
5. The ESP32 hosts a web dashboard showing live detection data and controls the physical sorting mechanism.

The app also runs a **background GPS tracking service** that logs the device's location to Supabase every 2 minutes, enabling fleet tracking of multiple sorting units.

**Key design decisions:**
- Models are NOT bundled in the APK -- users upload their own Teachable Machine models at runtime via ZIP or separate file picker.
- The inference pipeline supports a **dual preprocessing path**: native C++ with OpenCV (blur detection, CLAHE enhancement) and a pure-Dart fallback (runs in an isolate).
- ESP32 connection is optional -- the app works fully offline for classification, only needing WiFi for robot control.

---

## 2. Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Framework | Flutter | 3.10+ |
| Language | Dart | SDK ^3.10.4 |
| ML Inference | tflite_flutter | ^0.12.0 |
| Image Processing | image (Dart) | ^4.1.7 |
| Native Preprocessing | OpenCV (C++ via JNI) | 4.12.0 |
| Camera | camera | ^0.10.5+9 |
| State Management | Riverpod | ^3.2.1 |
| Backend | Supabase (Flutter) | ^2.12.0 |
| Persistence | shared_preferences | ^2.2.2 |
| HTTP Client | http | ^1.6.0 |
| File Handling | file_picker, archive, path_provider | various |
| Microcontroller | ESP32 (Arduino) | -- |
| Build System | Gradle 8.11.1, CMake 3.22.1, NDK | -- |
| Fonts | Google Fonts | ^8.0.2 |
| Location | geolocator | ^14.0.2 |
| Background Tasks | flutter_background_service | ^5.1.0 |

---

## 3. System Architecture

```
+-----------------------------------------------------------------------+
|                         ANDROID PHONE                                  |
|                                                                        |
|  +------------------+     +-------------------+     +---------------+  |
|  |   Camera Sensor  | --> | Preprocessing     | --> | TFLite        |  |
|  |   (YUV420)       |     | (dual path)       |     | Interpreter   |  |
|  |   ~15fps         |     |                   |     | [1,224,224,3] |  |
|  +------------------+     | Native: OpenCV    |     | -> [1, C]     |  |
|                           |   JNI C++ blur    |     +-------+-------+  |
|                           |   check + CLAHE   |             |          |
|                           |   + resize        |     +-------v-------+  |
|                           |                   |     | Detection     |  |
|                           | Dart: isolate     |     | Smoother      |  |
|                           |   YUV->RGB        |     | (temporal     |  |
|                           |   + resize        |     |  averaging)   |  |
|                           +-------------------+     +-------+-------+  |
|                                                             |          |
|  +------------------+     +-------------------+     +-------v-------+  |
|  | Detection Screen | <-- | Grid Mapper       | <-- | Detection     |  |
|  | (UI overlay +    |     | (8x8 Cartesian)   |     | (label, conf, |  |
|  |  result panel)   |     | pixel -> grid cell|     |  full-frame   |  |
|  +--------+---------+     +-------------------+     |  bounding box)|  |
|           |                                         +---------------+  |
|           |  HTTP POST                                                 |
+-----------+------------------------------------------------------------+
            |
            | WiFi (192.168.4.1)
            v
+-----------------------------------------------------------------------+
|                          ESP32                                         |
|                                                                        |
|  +------------------+     +-------------------+     +---------------+  |
|  | WiFi SoftAP      |     | Web Server :80    |     | Web Dashboard |  |
|  | "WESTO_BIN_01"   | --> | /ping             | --> | (HTML/JS)     |  |
|  |                  |     | /data   (POST)    |     | live updates  |  |
|  +------------------+     | /trigger (POST)   |     +---------------+  |
|                           | /api/latest (GET) |                        |
|                           +--------+----------+     +---------------+  |
|                                    |                | Robotic Arm   |  |
|                                    +--------------> | Motor Control |  |
|                                                     +---------------+  |
+-----------------------------------------------------------------------+
```

---

## 4. App Flow (User Journey)

```
main() -> SupabaseService.initialize() -> BackgroundService.initializeService()
       -> runApp(ProviderScope(child: WasteClassifierApp))
       -> ConnectionScreen (home)

ConnectionScreen
  |
  +-- "Test Connection" -> Esp32Service.checkConnection()
  |     |                   pings http://192.168.4.1/ping
  |     +-- success -> auto-proceed to _proceedToApp()
  |     +-- failure -> show "ESP32 Not Connected"
  |
  +-- "Skip for now" -> _proceedToApp()
  |
  _proceedToApp():
    |
    +-- model files missing? -> UploadScreen
    |     |
    |     +-- User uploads ZIP (model.tflite + labels.txt)
    |     |   OR picks files separately
    |     +-- ModelManager.extractZip() / saveModelFile() / saveLabelsFile()
    |     +-- Labels parsed and saved to SharedPreferences
    |     +-- Navigate to BinSetupScreen
    |
    +-- config missing or no bins? -> BinSetupScreen
    |     |
    |     +-- User creates bin categories (name, emoji, colour)
    |     +-- Maps model labels to bins (e.g. "plastic_bottle" -> "Recyclable")
    |     +-- Sets confidence threshold (slider, default 0.50)
    |     +-- Marks "nothing" labels to ignore
    |     +-- Saves AppConfig to SharedPreferences
    |     +-- Navigate to DetectionScreen
    |
    +-- everything ready -> DetectionScreen
          |
          +-- Initialises camera (back, ResolutionPreset.high, YUV420)
          +-- Loads TFLite model via DetectionService.initialize()
          +-- Starts image stream -> _onCameraFrame() at ~15fps
          +-- Each frame: preprocess -> classify -> smooth -> display
          +-- If ESP32 connected: transmit data every 1 second
```

---

## 5. Directory Structure

```
wasteclassifier/
|
|-- lib/
|   |-- main.dart                              # App entry point (32 lines)
|   |
|   |-- models/
|   |   |-- detection.dart                     # Detection + PreprocessResult classes (56 lines)
|   |   |-- app_config.dart                    # AppConfig: bins, threshold, nothingLabels (35 lines)
|   |   |-- bin_category.dart                  # BinCategory: id, name, emoji, color, labels (48 lines)
|   |   |-- calibration_config.dart            # Homography + camera geometry calibration (241 lines)
|   |
|   |-- screens/
|   |   |-- connection_screen.dart             # ESP32 WiFi connection check (268 lines)
|   |   |-- upload_screen.dart                 # Model + labels file upload UI (835 lines)
|   |   |-- bin_setup_screen.dart              # Bin category CRUD + label mapping (786 lines)
|   |   |-- detection_screen.dart              # Main camera + classification screen (1048 lines)
|   |   |-- camera_screen.dart                 # Alternate camera screen (167 lines)
|   |
|   |-- services/
|   |   |-- detection_service.dart             # TFLite classification orchestrator (148 lines)
|   |   |-- opencv_pipeline.dart               # Native OpenCV bridge + Dart fallback (131 lines)
|   |   |-- dart_preprocessor.dart             # Pure-Dart YUV->RGB resize in isolate (152 lines)
|   |   |-- detection_smoother.dart            # Temporal smoothing with IoU matching (97 lines)
|   |   |-- nms_processor.dart                 # [LEGACY] YOLO NMS + letterbox unmapping (143 lines)
|   |   |-- esp32_service.dart                 # ESP32 HTTP singleton (127 lines)
|   |
|   |-- utils/
|   |   |-- detection_constants.dart           # All tuneable pipeline constants (17 lines)
|   |   |-- model_manager.dart                 # Model file I/O, ZIP extraction, label parsing (137 lines)
|   |   |-- config_manager.dart                # SharedPreferences CRUD for config (80 lines)
|   |   |-- waste_locator.dart                 # Direction zones + distance estimation (219 lines)
|   |
|   |-- core/
|   |   |-- grid_mapper.dart                   # 8x8 center-origin grid mapping (194 lines)
|   |   |-- supabase_client.dart               # Supabase init + Riverpod provider (17 lines)
|   |   |-- location_service.dart              # GPS/GSM location with permissions (89 lines)
|   |   |-- background_service.dart            # Periodic GPS -> Supabase upload (105 lines)
|   |   |-- http_server.dart                   # Shelf HTTP server for data reception (59 lines)
|   |
|   |-- communication/
|   |   |-- robot_controller.dart              # Grid -> robot command creation + HTTP send (71 lines)
|   |
|   |-- widgets/
|   |   |-- detection_overlay.dart             # Classification label banner with animations (290 lines)
|   |   |-- camera_preview_frame.dart          # Camera preview with grid painter (47 lines)
|   |   |-- top_bar.dart                       # Scanning badge, bin setup button (134 lines)
|   |   |-- bottom_info_sheet.dart             # Scanning status text (67 lines)
|   |   |-- axis_labels.dart                   # X/Y axis label widgets for grid (112 lines)
|   |
|   |-- ui/
|   |   |-- grid_overlay_painter.dart          # 8x8 grid CustomPainter with active cell (291 lines)
|   |
|   |-- painters/
|   |   |-- grid_painter.dart                  # Basic 8x8 grid CustomPainter (59 lines)
|   |
|   |-- theme/
|   |   |-- app_theme.dart                     # Dark theme colours and constants (33 lines)
|   |
|   |-- shared/
|       |-- constants.dart                     # App-wide constants: ESP32 IP, Supabase config (19 lines)
|       |-- models/
|           |-- location_log.dart              # LocationLog model for Supabase (35 lines)
|           |-- waste_detection.dart           # WasteDetection model for Supabase (45 lines)
|
|-- android/
|   |-- app/
|   |   |-- build.gradle.kts                   # compileSdk 36, minSdk 24, CMake + NDK config (89 lines)
|   |   |-- src/main/
|   |       |-- AndroidManifest.xml            # Permissions: CAMERA, INTERNET, LOCATION, etc. (65 lines)
|   |       |-- kotlin/.../
|   |       |   |-- MainActivity.kt            # MethodChannel handler for opencv_pipeline (250 lines)
|   |       |   |-- OpenCVHelper.kt            # JNI wrapper loading libyolo_preprocess.so (141 lines)
|   |       |-- cpp/
|   |           |-- yolo_preprocess.cpp         # Native C++: YUV->BGR, blur, CLAHE, resize (524 lines)
|   |           |-- CMakeLists.txt              # CMake build: optional OpenCV, HAVE_OPENCV flag (46 lines)
|   |
|   |-- build.gradle.kts                       # AGP 8.11.1, Kotlin 2.2.20 (24 lines)
|   |-- settings.gradle.kts                    # Plugin management (26 lines)
|   |-- local.properties                       # SDK paths + opencv.sdk.path (10 lines)
|   |-- OpenCV-android-sdk/                    # OpenCV 4.12.0 Android SDK (in-tree)
|
|-- esp32/
|   |-- firmware.ino                           # Arduino ESP32 firmware: WiFi AP + web server (303 lines)
|
|-- test/
|   |-- model_manager_test.dart                # Label parsing + file existence tests (148 lines)
|   |-- nms_processor_test.dart                # NMS + letterbox unmapping tests (217 lines)
|   |-- grid_mapper_test.dart                  # Grid mapping tests (183 lines)
|   |-- widget_test.dart                       # App startup smoke test (9 lines)
|
|-- scripts/
|   |-- augment_check.py                       # Dataset audit + augmentation recommendations (260 lines)
|
|-- pubspec.yaml                               # Dependencies + Flutter config (61 lines)
|-- analysis_options.yaml                      # Lint rules (28 lines)
|-- DOCUMENTATION.md                           # This file
|-- APP_DOCUMENTATION.md                       # Earlier app documentation (582 lines)
```

---

## 6. Screens

### 6.1 ConnectionScreen (`lib/screens/connection_screen.dart`, 268 lines)

The launch screen. Presents an "ESP32 Link" interface with:
- **Test Connection** button: pings `http://192.168.4.1/ping` via `Esp32Service.checkConnection()`.
- On success: shows "ESP32 Connected", then auto-navigates after 1 second.
- On failure: shows "ESP32 Not Connected" in red.
- **Skip for now** button: proceeds without ESP32 (classification works, but no robot commands).

Navigation logic (`_proceedToApp()`):
1. If model files don't exist on disk -> `UploadScreen`
2. If config is null or has no bins -> `BinSetupScreen`
3. Otherwise -> `DetectionScreen`

### 6.2 UploadScreen (`lib/screens/upload_screen.dart`, 835 lines)

Allows the user to upload their Teachable Machine model. Two methods via a `TabBar`:

**Tab 1 -- ZIP Upload:**
- User picks a `.zip` file via `file_picker`.
- `ModelManager.extractZip()` scans the archive for `model.tflite` and `labels.txt`.
- Reports errors if either file is missing.

**Tab 2 -- Separate Files:**
- Two separate file picker buttons: one for `.tflite`, one for `.txt`.
- Files copied to `getApplicationDocumentsDirectory()`.

After successful upload:
- Labels are parsed by `ModelManager.parseLabelsFile()` (strips leading index numbers like `"0 ClassName"` from Teachable Machine format).
- Labels saved to SharedPreferences via `ConfigManager.saveLabels()`.
- `ConfigManager.setModelLoaded(true)`.
- Navigates to `BinSetupScreen`.

### 6.3 BinSetupScreen (`lib/screens/bin_setup_screen.dart`, 786 lines)

Configuration screen where the user:
1. **Creates bin categories** -- Each bin has: name, emoji, hex colour, and a list of mapped labels.
2. **Maps model labels to bins** -- e.g., "plastic_bottle" and "glass_jar" -> "Recyclable" bin.
3. **Sets confidence threshold** -- Slider from 0 to 1.0 (default: 0.50). Detections below this are ignored.
4. **Marks "nothing" labels** -- Labels like "background" or "empty" that should not trigger detection.

Saves the complete `AppConfig` to SharedPreferences and navigates to `DetectionScreen`.

### 6.4 DetectionScreen (`lib/screens/detection_screen.dart`, 1048 lines)

The main operational screen. Locked to **landscape orientation** (left or right). Components:

**Camera setup:**
- Back camera at `ResolutionPreset.high` with `ImageFormatGroup.yuv420`.
- Image stream feeds `_onCameraFrame()` which gates on `_isProcessing` and `_modelReady`.

**Inference loop (`_runInference()`):**
1. Calls `_detectionService.processFrame(image)` -- returns 0 or 1 `Detection` objects.
2. If no detections: set state to `DetectionState.waiting`, clear grid position.
3. If detection present: pick highest-confidence, compute pixel center, call `_processResult()`.

**Result processing (`_processResult()`):**
1. Check against `config.confidenceThreshold` -- below threshold -> waiting.
2. Check against `config.nothingLabels` -- if label is "nothing" -> waiting.
3. Match label to a `BinCategory` from config.
4. Compute `GridPosition` via `GridMapper.fromPixel()`.
5. Compute `WasteLocation` via `WasteLocator.compute()`.
6. If ESP32 connected and bin matched: transmit via `_transmitToEsp32()`.

**UI layout (landscape Stack):**
- Full-screen camera preview inside `AspectRatio`.
- `DetectionOverlay` -- classification label banner (top-center).
- `Grid8x8Overlay` -- 8x8 grid with active cell highlight and pulsing animation.
- Status badge (top-left) -- "SCANNING" / "DETECTED" / "LOADING".
- Action buttons (top-right) -- Bin Setup, Change Model, ESP32 Trigger.
- Bottom result panel -- detected label, confidence, grid coordinate badge, bin chip, robot command, distance estimate.

---

## 7. Inference Pipeline

This section traces a single camera frame through the entire classification pipeline.

### Step 1: Frame Capture

```
CameraController.startImageStream(_onCameraFrame)
```

The camera delivers `CameraImage` objects in YUV420 format. The `_onCameraFrame` callback checks two gates:
- `_isProcessing` -- prevents concurrent inference (one frame at a time).
- `_modelReady` -- ensures the TFLite interpreter is loaded.

### Step 2: Throttle Check

```dart
// detection_service.dart:34
bool _shouldRunInference() {
  final now = DateTime.now();
  if (now.difference(_lastInference).inMilliseconds < kMaxFpsMs) return false;
  _lastInference = now;
  return true;
}
```

`kMaxFpsMs = 66` limits inference to ~15 FPS. Frames arriving faster are silently dropped.

### Step 3: Preprocessing

```dart
// detection_service.dart:73
final preprocessed = await OpenCVPipeline.preprocessFrame(image);
```

See [Section 8](#8-preprocessing-dual-path) for the dual-path details. The output is a `PreprocessResult` containing a `Float32List` of shape `[224 * 224 * 3]` with values normalised to `[0, 1]` in NHWC order.

### Step 4: TFLite Classification

```dart
// detection_service.dart:77
final result = _runClassification(preprocessed.floatData);
```

Inside `_runClassification()`:
1. Query output tensor shape: `[1, numClasses]`.
2. Wrap float data as `Float32List`.
3. Allocate output buffer: `List<double>.filled(numClasses, 0.0)`.
4. Run `_interpreter!.run([input], output)`.
5. Find argmax: iterate output to find the class with highest probability.
6. Map index to label from `_labels` list.
7. Return `(label, confidence)` tuple.

### Step 5: Confidence Gate

```dart
// detection_service.dart:83
if (confidence < kConfidenceThreshold) {
  return _smoother.smooth([]);
}
```

`kConfidenceThreshold = 0.40`. If the top class probability is below this, an empty list is passed to the smoother (which helps clear old detections from the rolling window).

### Step 6: Build Detection Object

```dart
// detection_service.dart:87
final detection = Detection(
  box: Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
  label: label,
  confidence: confidence,
);
```

Since Teachable Machine classifies the **entire frame** (not individual objects), the bounding box spans the full frame dimensions. This is a deliberate design: downstream code that expects a `Detection` with a `.box` still works, and the box center maps to the frame center for grid positioning.

### Step 7: Temporal Smoothing

```dart
// detection_service.dart:94
return _smoother.smooth([detection]);
```

`DetectionSmoother` maintains a rolling window of the last `kSmootherWindowSize = 5` frames. It groups detections across frames by label + IoU matching (`kSmootherMatchIou = 0.3`). A detection must appear in at least `kSmootherMinAppearances = 2` of the last 5 frames to be emitted.

For full-frame classification boxes (identical `Rect` each frame), IoU is always 1.0 when the label matches. This effectively becomes **temporal voting**: a label must be predicted in at least 2 of the last 5 frames to be reported.

The smoother also averages confidence across matched frames, reducing flicker.

### Step 8: Display and Action

The `DetectionScreen` receives the smoothed list (0 or 1 items) and:
1. Updates `_currentDetections` -> triggers `DetectionOverlay` rebuild.
2. Picks the best detection -> computes pixel center -> calls `_processResult()`.
3. `_processResult()` runs grid mapping, waste location, bin matching, and ESP32 transmission.

---

## 8. Preprocessing: Dual Path

The app has two independent preprocessing paths. The native path is preferred but the Dart fallback ensures the app works on any device.

### 8.1 Path Selection (`opencv_pipeline.dart`)

```dart
static Future<PreprocessResult?> preprocessFrame(CameraImage image) async {
  final native = await isNativeAvailable();  // cached after first call

  if (native) {
    final result = await _tryNative(image);
    if (result != null) return result;        // success
    if (_lastFrameWasBlurry) return null;      // blurry -> skip entirely
    // else: JNI error -> fall through to Dart
  }

  return DartPreprocessor.preprocessFrame(image);  // Dart fallback
}
```

Key behaviour:
- **Native available + success**: use native result.
- **Native available + blurry frame**: return `null` (frame skipped, no fallback).
- **Native available + JNI error**: fall through to Dart fallback for this frame only. The native path stays enabled for the next frame (`_nativeReady` is NOT reset on per-frame errors).
- **Native unavailable**: always use Dart fallback.

### 8.2 Native Path (OpenCV C++ via JNI)

**Call chain:**
```
Dart OpenCVPipeline._tryNative()
  -> MethodChannel 'opencv_pipeline' / 'preprocess_frame'
  -> MainActivity.kt handlePreprocessFrame()
  -> OpenCVHelper.preprocessFrame() (JNI)
  -> yolo_preprocess.cpp Java_..._preprocessFrame()
```

**What the C++ does (`yolo_preprocess.cpp:328-384`):**
1. **YUV420 -> BGR** conversion using OpenCV `cvtColor(COLOR_YUV2BGR_NV21)`.
2. **Blur detection** -- computes Laplacian variance. If below `kBlurSkipThreshold` (100.0), returns a sentinel float array with `skipped = 1.0`.
3. **CLAHE** (Contrast Limited Adaptive Histogram Equalisation) -- enhances local contrast, particularly useful in varying lighting conditions on a conveyor.
4. **Resize** to `kInputSize x kInputSize` (224x224).
5. **Normalise** to `[0, 1]` float32 in NHWC order.
6. **Append 4 metadata floats**: `[padLeft, padTop, scale, skipped]`.

**Return value:** `Float32List` of length `224*224*3 + 4 = 150532`.

### 8.3 Dart Fallback Path (`dart_preprocessor.dart`)

Runs entirely in a Dart `compute()` isolate to avoid blocking the UI thread.

**Steps in `_runPreprocess()` (isolate entry point):**
1. **YUV420 -> RGB** -- Manual pixel-by-pixel conversion using standard YUV-to-RGB coefficients:
   ```
   R = Y + 1.402 * (V - 128)
   G = Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)
   B = Y + 1.772 * (U - 128)
   ```
2. **Simple resize** to 224x224 using `img.copyResize()` from the `image` package. This is a standard bilinear resize (no letterbox padding), matching how Teachable Machine models are trained.
3. **Normalise** to `[0, 1]` float32 in NHWC order: `pixel.r / 255.0`, etc.

**What this path does NOT do:**
- No blur detection (all frames are processed).
- No CLAHE enhancement.
- Slightly slower than native C++ but fully functional for inference.

### 8.4 Comparison

| Feature | Native (OpenCV) | Dart Fallback |
|---------|----------------|---------------|
| Blur detection | Laplacian variance check | None |
| Contrast enhancement | CLAHE | None |
| Resize method | OpenCV resize | `image` package `copyResize` |
| Thread | Platform thread (JNI) | Dart isolate |
| Performance | Faster (~5-10ms) | Slower (~20-40ms) |
| Availability | Requires OpenCV SDK in build | Always available |
| Normalisation | [0, 1] NHWC float32 | [0, 1] NHWC float32 |

---

## 9. Teachable Machine Model Specification

### 9.1 Model Format

TrashSense is built exclusively for **Google Teachable Machine image classification** models (NOT object detection).

| Property | Value |
|----------|-------|
| Export format | TensorFlow Lite (Floating Point) |
| Input tensor | `[1, 224, 224, 3]` -- batch=1, height=224, width=224, channels=3 (RGB) |
| Input layout | NHWC (batch, height, width, channels) |
| Input dtype | float32 |
| Input range | `[0.0, 1.0]` (pixel values divided by 255) |
| Output tensor | `[1, numClasses]` -- flat probability vector |
| Output dtype | float32 |
| Output range | `[0.0, 1.0]` (softmax probabilities summing to ~1.0) |

### 9.2 How Models Are Loaded

Models are **not bundled** in the APK. The user uploads them at runtime:

1. **Upload** -- Via `UploadScreen`, user picks a ZIP file or separate `model.tflite` + `labels.txt` files.
2. **Extract** -- `ModelManager.extractZip()` scans the ZIP for files named `model.tflite` and `labels.txt` (case-insensitive, ignores directory structure).
3. **Store** -- Files are copied to `getApplicationDocumentsDirectory()`:
   - `<app_docs>/model.tflite`
   - `<app_docs>/labels.txt`
4. **Parse labels** -- `ModelManager.parseLabelsFile()` reads `labels.txt` and:
   - Splits on `\r\n`, `\r`, or `\n` (handles all line ending formats).
   - Strips leading index numbers (Teachable Machine format: `"0 ClassName"` -> `"ClassName"`).
   - Removes empty lines.
5. **Cache** -- Parsed label list saved to SharedPreferences via `ConfigManager.saveLabels()`.
6. **Load** -- `DetectionService.initialize()` opens the model file with `Interpreter.fromFile()` (2 threads) and stores the label list.

### 9.3 Labels File Format

Teachable Machine exports `labels.txt` with indexed entries:

```
0 Plastic
1 Paper
2 Metal
3 Glass
4 Organic
5 Nothing
```

The parser (`ModelManager.parseLabelsFile()`) detects the leading integer and strips it, producing: `["Plastic", "Paper", "Metal", "Glass", "Organic", "Nothing"]`.

Plain format (one name per line, no index) is also supported.

---

## 10. 8x8 Grid Mapping System

### 10.1 Concept

The camera frame is divided into an **8x8 grid** with a **center-origin Cartesian coordinate system**:

```
        -4   -3   -2   -1    0    1    2    3    <- X axis
      +----+----+----+----+----+----+----+----+
  +3  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
  +2  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
  +1  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
   0  |    |    |    |  (0,0)  |    |    |    |
      +----+----+----+---++---+----+----+----+
  -1  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
  -2  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
  -3  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
  -4  |    |    |    |    |    |    |    |    |
      +----+----+----+----+----+----+----+----+
   ^
   Y axis (positive = up)
```

- Origin `(0, 0)` is at the **center of the frame**.
- **Positive X** = right, **Negative X** = left.
- **Positive Y** = up, **Negative Y** = down.
- Grid cells range from `(-4, -4)` to `(3, 3)`.

### 10.2 Conversion Pipeline (`GridMapper`)

```dart
// grid_mapper.dart:172
static GridPosition fromPixel({
  required double pixelX,
  required double pixelY,
  int frameWidth = 640,
  int frameHeight = 640,
}) {
  final double centerX = pixelX - frameWidth / 2;   // pixels from center
  final double centerY = frameHeight / 2 - pixelY;  // Y inverted (up = positive)
  final int gridX = (centerX / (frameWidth / 8)).floor();
  final int gridY = (centerY / (frameHeight / 8)).floor();
  return GridPosition(gridX, gridY, pixelX, pixelY, centerX, centerY);
}
```

### 10.3 Classification and Grid Mapping

For Teachable Machine classification (whole-frame), the detection box is `Rect.fromLTWH(0, 0, frameWidth, frameHeight)`. The center pixel is always `(frameWidth/2, frameHeight/2)`, which maps to grid cell `(0, 0)` -- directly under the camera.

This is physically correct for a top-down mounted camera: "object detected in frame" means "object is at the camera's center position".

### 10.4 GridPosition Model

```dart
class GridPosition {
  final int gridX;       // Grid column: -4 to +3
  final int gridY;       // Grid row: -4 to +3
  final int pixelX;      // Raw pixel X
  final int pixelY;      // Raw pixel Y
  final double centerX;  // Pixels from frame center (X)
  final double centerY;  // Pixels from frame center (Y)
  final String action;   // Default: "pick"
}
```

Serialises to JSON for ESP32 transmission:
```json
{ "grid_x": 0, "grid_y": 0, "pixel_x": 540, "pixel_y": 960, "action": "pick" }
```

---

## 11. ESP32 Communication Protocol

### 11.1 Network Setup

The ESP32 runs as a **WiFi SoftAP** (access point):
- **SSID:** `WESTO_BIN_01`
- **Password:** `password123`
- **IP:** `192.168.4.1` (ESP32 SoftAP default gateway)

The phone connects to this WiFi network. All communication is HTTP over this local network.

### 11.2 Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/ping` | Health check. Returns 200 if ESP32 is alive. |
| `POST` | `/data` | Send waste classification data or robot command. |
| `POST` | `/trigger` | Send a trigger signal to initiate robot action. |
| `GET` | `/api/latest` | Retrieve the most recent detection data (for dashboard). |
| `GET` | `/` | Serves the HTML web dashboard. |

### 11.3 Waste Data Payload (`POST /data`)

Sent by `Esp32Service.sendWasteData()`:

```json
{
  "timestamp": "2026-03-17T10:30:00.000Z",
  "label": "plastic_bottle",
  "binId": "bin_1",
  "binName": "Recyclable",
  "confidence": 0.87,
  "direction": "center",
  "distanceCm": 45.0,
  "coordX": 0.0,
  "coordY": 0.0,
  "gridCell": "(0, 0)",
  "pixelX": 540,
  "pixelY": 960
}
```

### 11.4 Robot Command Payload (`POST /data`)

Sent by `Esp32Service.sendRobotCommand()`:

```json
{
  "object_detected": true,
  "coordinates": {
    "x": 0,
    "y": 0
  }
}
```

### 11.5 Trigger Payload (`POST /trigger`)

```json
{ "trigger": 1 }
```

### 11.6 Throttling

`DetectionScreen` throttles ESP32 transmissions to **once per second** (1000ms minimum between sends) to avoid overwhelming the microcontroller.

### 11.7 ESP32 Firmware (`esp32/firmware.ino`, 303 lines)

Arduino sketch running on the ESP32:
- Creates WiFi SoftAP with `WiFi.softAP(ssid, password)`.
- Runs `WebServer` on port 80.
- `GET /` serves a full HTML/CSS/JS dark-themed dashboard that auto-refreshes detection data via `fetch('/api/latest')`.
- `POST /data` stores the received JSON payload and updates `lastPayload`.
- `POST /trigger` triggers the robotic arm control logic.
- `GET /api/latest` returns the most recent payload as JSON.

---

## 12. Robot Navigation (WasteLocator)

`WasteLocator` (`lib/utils/waste_locator.dart`, 219 lines) converts pixel coordinates and confidence into navigation commands for the robot.

### 12.1 Direction Zones

The frame is split into three horizontal zones:

```
|<--- LEFT --->|<--- CENTER --->|<--- RIGHT --->|
0.0          0.35             0.65             1.0
```

- `normX < 0.35` -> `WasteDirection.left` -> `"TURN LEFT"`
- `0.35 <= normX <= 0.65` -> `WasteDirection.center` -> `"GO STRAIGHT"`
- `normX > 0.65` -> `WasteDirection.right` -> `"TURN RIGHT"`

### 12.2 Speed and Stop Logic

| Confidence Range | Speed Hint | Robot Command |
|-----------------|------------|---------------|
| >= 0.95 | `stop` | `"STOP + PICK UP"` (overrides direction) |
| 0.80 -- 0.95 | `slow` | Direction-based command |
| < 0.80 | `fast` | Direction-based command |

### 12.3 Distance Estimation

Two methods:

**Calibration-based** (when `CalibrationConfig` is provided):
- Uses homography matrix (computed from 4 reference point pairs via DLT) to map pixel coordinates to real-world cm coordinates.
- Or uses camera-height geometry: `distance = (cameraHeightCm * focalLengthPx) / pixelY`.

**Confidence-based heuristic** (fallback):
- Maps confidence linearly to distance: 60% confidence -> ~120cm, 95%+ confidence -> ~10cm.
- Formula: `dist = 120 - 110 * ((confidence - 0.6) / 0.4)`

### 12.4 WasteLocation Output

```dart
class WasteLocation {
  final WasteDirection direction;      // left / center / right / unknown
  final double? estimatedDistanceCm;   // distance in cm
  final String robotCommand;           // "TURN LEFT", "GO STRAIGHT", "STOP + PICK UP", etc.
  final String speedHint;              // "fast", "slow", "stop"
  final double normX, normY;           // normalised frame coordinates
  final int pixelX, pixelY;            // raw pixel coordinates
  final double? realWorldX, realWorldY; // cm from homography (optional)
}
```

---

## 13. Detection Overlay (UI)

`DetectionOverlay` (`lib/widgets/detection_overlay.dart`, 290 lines) renders the classification result on top of the camera preview.

### 13.1 Visual Design

Since Teachable Machine classifies the entire frame (no bounding boxes), the overlay renders:

1. **Subtle frame border** -- A thin coloured border around the entire preview with 6% opacity fill and 35% opacity stroke. The colour is assigned per-label from a 10-colour palette.
2. **Centered label badge** -- A rounded rectangle at the top-center of the frame showing `"ClassName  85%"` in white text on a coloured background (85% opacity).

### 13.2 Animation System

Each classification result is wrapped in a `_TrackedDetection` with its own `AnimationController`:

- **Fade-in:** 150ms when a new label appears.
- **Fade-out:** 300ms when a label disappears or changes.

The `_reconcile()` method matches incoming detections to existing tracked entries using **IoU + label** matching:
- Same label + IoU >= `kSmootherMatchIou` (0.3) -> update in place (no animation restart).
- No match found for existing -> start fade-out, remove when animation completes.
- No match found for incoming -> create new entry, start fade-in.

For full-frame classification (identical `Rect` each frame), IoU is always 1.0 when the label matches. When the label changes, the old label fades out and the new one fades in simultaneously, creating a smooth crossfade effect.

### 13.3 Colour Palette

Labels are assigned colours from a 10-colour palette in order of first appearance:

```
green (#00E676), cyan (#00B0FF), red (#FF5252), amber (#FFD740),
purple (#E040FB), teal (#18FFFF), light-green (#69F0AE),
light-blue (#40C4FF), pink (#FF4081), deep-orange (#FF6E40)
```

The mapping is stable within a session -- once a label is assigned a colour, it keeps it.

---

## 14. Native C++ / OpenCV Integration

### 14.1 Architecture

```
Dart (OpenCVPipeline)
  |
  | MethodChannel 'opencv_pipeline'
  v
Kotlin (MainActivity.kt)
  |
  | Function dispatch based on method name
  v
Kotlin (OpenCVHelper.kt)
  |
  | JNI external native functions
  v
C++ (yolo_preprocess.cpp)
  |
  | OpenCV 4.12.0 (statically linked)
  v
libyolo_preprocess.so (9.3MB)
```

### 14.2 MethodChannel Methods

| Method | Purpose |
|--------|---------|
| `is_opencv_available` | Returns `true` if native lib loaded with OpenCV |
| `preprocess_frame` | Full-frame preprocessing for classification |
| `preprocess_zone` | Single zone preprocessing (legacy) |
| `preprocess_horizontal_zones` | Horizontal strip preprocessing (legacy) |
| `preprocess_grid_zones` | Batch grid zone preprocessing (legacy) |

Only `is_opencv_available` and `preprocess_frame` are used in the current TM pipeline. The zone-based methods are retained from the earlier YOLO-based architecture.

### 14.3 C++ Functions (`yolo_preprocess.cpp`, 524 lines)

The file contains 5 JNI entry points. The primary one for the current pipeline:

**`preprocessFrame()`:**
1. Receives YUV420 plane data (`y_plane`, `u_plane`, `v_plane`) + dimensions + target size + blur threshold.
2. Combines Y + UV planes into NV21 format.
3. `cvtColor(COLOR_YUV2BGR_NV21)` -- converts to BGR.
4. Computes Laplacian variance for blur detection. If below threshold, returns sentinel array.
5. Applies CLAHE to the L channel of LAB colour space.
6. Resizes to `target_size x target_size` (224x224).
7. Normalises to `[0, 1]` float32 in NHWC order.
8. Appends 4 metadata floats: `[padLeft, padTop, scale, skipped]`.
9. Returns as `jfloatArray`.

### 14.4 Build System

**CMakeLists.txt** (`android/app/src/main/cpp/CMakeLists.txt`):
- Minimum CMake 3.22.1.
- Conditionally finds OpenCV if `OPENCV_SDK_DIR` is set.
- Defines `HAVE_OPENCV` compile flag when OpenCV is found.
- Links `libyolo_preprocess.so` against OpenCV static libs.

**app/build.gradle.kts:**
- Passes `OPENCV_SDK_DIR` to CMake from `local.properties`:
  ```
  cmake {
    arguments("-DOPENCV_SDK_DIR=${opencvSdkDir}")
  }
  ```
- NDK ABI filters: `arm64-v8a`, `armeabi-v7a`.

**local.properties:**
```
opencv.sdk.path=/path/to/wasteclassifier/android/OpenCV-android-sdk
```

### 14.5 LSP False Positives

The C++ file shows errors in IDEs (`jni.h not found`, `JNIEXPORT unknown`). These are **LSP false positives** -- the file compiles correctly through the Android NDK build system which provides the JNI headers. These errors should be ignored.

---

## 15. Background Services

### 15.1 GPS Location Tracking

`BackgroundService` (`lib/core/background_service.dart`, 105 lines) runs a periodic timer in a background isolate:

1. **Every 2 minutes**, checks `SharedPreferences` for `location_tracking_enabled` flag.
2. If enabled, calls `LocationService.getCurrentLocation()` via `geolocator`.
3. Creates a `LocationLog` with lat/lng/timestamp/deviceId.
4. Inserts into Supabase `location_logs` table.

The service runs even when the app is in the background (via `flutter_background_service` with `isForegroundMode: true`).

### 15.2 Supabase Integration

`SupabaseService` (`lib/core/supabase_client.dart`) initialises the Supabase client with URL and anon key from `AppConstants`. The background service re-initialises Supabase in its own isolate since it runs separately from the main app.

**Tables:**
| Table | Fields |
|-------|--------|
| `location_logs` | latitude, longitude, recorded_at, device_id |
| `waste_detections` | label, confidence, bin_name, grid_x, grid_y, timestamp, device_id |

### 15.3 Android Permissions

From `AndroidManifest.xml`:
```
CAMERA, INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION,
ACCESS_BACKGROUND_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION,
RECEIVE_BOOT_COMPLETED, WAKE_LOCK, POST_NOTIFICATIONS
```

---

## 16. Configuration and Persistence

### 16.1 ConfigManager (`lib/utils/config_manager.dart`)

All configuration is stored in `SharedPreferences` under these keys:

| Key | Type | Content |
|-----|------|---------|
| `app_config` | JSON string | Serialised `AppConfig` (bins, threshold, nothingLabels) |
| `labels_list` | JSON string | Array of label strings `["Plastic", "Paper", ...]` |
| `model_loaded` | bool | Whether model files have been uploaded |
| `calibration_config` | JSON string | Serialised `CalibrationConfig` (optional) |

### 16.2 AppConfig

```dart
class AppConfig {
  List<BinCategory> bins;          // Bin categories with mapped labels
  double confidenceThreshold;      // Default: 0.50
  List<String> nothingLabels;      // Labels to ignore (e.g. "background")
}
```

### 16.3 BinCategory

```dart
class BinCategory {
  String id;                       // Unique ID (UUID)
  String name;                     // Display name (e.g. "Recyclable")
  String emoji;                    // Visual identifier (e.g. "recycling symbol")
  int colorHex;                    // Hex colour (e.g. 0xFF00E676)
  List<String> mappedLabels;       // Model labels mapped to this bin
}
```

### 16.4 CalibrationConfig

Optional camera calibration supporting:
- **Camera-height geometry:** `cameraHeightCm` (default 150cm) + `focalLengthPx` (default 800px).
- **Homography:** 4 pixel-to-real-world point pairs. Computes a 3x3 perspective transform matrix via DLT (Direct Linear Transform) with Gaussian elimination. Stored as 9-element row-major array.

---

## 17. Dependencies

### Production Dependencies (17)

| Package | Version | Purpose |
|---------|---------|---------|
| `cupertino_icons` | ^1.0.8 | iOS-style icons |
| `camera` | ^0.10.5+9 | Camera access and YUV420 image stream |
| `tflite_flutter` | ^0.12.0 | TensorFlow Lite inference on-device |
| `image` | ^4.1.7 | Pure-Dart image manipulation (YUV->RGB, resize) |
| `file_picker` | ^8.0.0+1 | File selection for model upload |
| `path_provider` | ^2.1.2 | App documents directory path |
| `path` | ^1.9.0 | Cross-platform path manipulation |
| `shared_preferences` | ^2.2.2 | Persistent key-value storage |
| `flutter_colorpicker` | ^1.0.3 | Colour picker widget for bin setup |
| `archive` | ^4.0.0 | ZIP file extraction |
| `google_fonts` | ^8.0.2 | Inter and Roboto Mono fonts |
| `http` | ^1.6.0 | HTTP client for ESP32 communication |
| `supabase_flutter` | ^2.12.0 | Supabase backend integration |
| `geolocator` | ^14.0.2 | GPS location services |
| `flutter_background_service` | ^5.1.0 | Background execution for GPS tracking |
| `shelf` | ^1.4.2 | HTTP server for data reception |
| `device_info_plus` | ^12.3.0 | Device ID for tracking |
| `flutter_riverpod` | ^3.3.1 | State management |
| `riverpod` | ^3.2.1 | Core Riverpod package |

### Dev Dependencies (4)

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Testing framework |
| `flutter_lints` | ^6.0.0 | Lint rules |
| `flutter_launcher_icons` | ^0.14.4 | App icon generation |
| `plugin_platform_interface` | ^2.1.8 | Platform interface for testing |
| `path_provider_platform_interface` | ^2.1.2 | Path provider mock for testing |

---

## 18. Test Suite

### 18.1 Overview

| File | Tests | What's Tested |
|------|-------|---------------|
| `test/model_manager_test.dart` | 10 | Label parsing (LF, CRLF, CR line endings), indexed format stripping, empty-line filtering, `modelFilesExist()` |
| `test/nms_processor_test.dart` | 7 | NMS on identical/overlapping boxes, same/different class handling, letterbox unmapping, confidence filtering, empty input [LEGACY -- NMS no longer called in TM pipeline] |
| `test/grid_mapper_test.dart` | 21 | `calculateObjectCenter`, `convertToCenterCoordinates`, `computeGridCell`, `fromPixel` (center, corners, edges, non-square frames), `fromBoundingBox`, `toJson` |
| `test/widget_test.dart` | 1+ | App startup smoke test |
| **Total** | **38+** | |

### 18.2 Running Tests

```bash
# Run all tests
flutter test

# Run a specific test file
flutter test test/grid_mapper_test.dart

# Run with verbose output
flutter test --reporter expanded
```

### 18.3 Analyzer

```bash
# Run static analysis (should report 0 issues)
dart analyze lib/
```

---

## 19. Build and Run Instructions

### 19.1 Prerequisites

- Flutter SDK 3.10.4+
- Android SDK with compileSdk 36
- Android NDK (for native C++ compilation)
- OpenCV 4.12.0 Android SDK (optional -- app works without it via Dart fallback)

### 19.2 OpenCV Setup (Optional)

1. Download OpenCV Android SDK 4.12.0.
2. Place it at `android/OpenCV-android-sdk/` (already in the project tree).
3. Ensure `android/local.properties` contains:
   ```
   opencv.sdk.path=/absolute/path/to/wasteclassifier/android/OpenCV-android-sdk
   ```
4. The CMake build will automatically detect it and compile with `HAVE_OPENCV`.

Without OpenCV, the native `is_opencv_available` call returns `false` and all preprocessing uses the Dart fallback.

### 19.3 Build Commands

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# Run on connected device
flutter run

# Run with Supabase credentials
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
            --dart-define=SUPABASE_ANON_KEY=your_key
```

### 19.4 First Launch

1. Connect phone to ESP32 WiFi (`WESTO_BIN_01` / `password123`) -- or skip.
2. Upload your Teachable Machine model (ZIP export with `model.tflite` + `labels.txt`).
3. Set up bin categories and map labels to bins.
4. Point camera at waste items -- classification results appear in real-time.

---

## 20. Git History and Branches

### 20.1 Branches

| Branch | Status | Description |
|--------|--------|-------------|
| `master` | Tagged `v1` | Stable release with basic detection |
| `theme-manipulation` | Merged to master | UI theming changes |
| `stable-version-v1` | Diverged from master | OpenCV integration, batch processing |
| `performace` | Diverged | Dotenv, background service, JNI optimisation |
| `detection-improvement` | **Current HEAD** | Full-frame pipeline, TM rewrite, animated overlay |

### 20.2 Development Timeline

**Phase 1 -- Foundation:**
Project bootstrapped, initial Flutter app structure.

**Phase 2 -- Core App:**
Upload screen, bin setup screen, detection screen, camera integration, grid-based robotic arm control, ESP32 communication.

**Phase 3 -- Backend:**
Supabase integration, background GPS location tracking.

**Phase 4 -- Theme and Branding:**
Rebranded to "TrashSense", UI theming, merged as PR #1.

**Phase 5 -- Native OpenCV:**
JNI bridge (`yolo_preprocess.cpp`, `OpenCVHelper.kt`, `MainActivity.kt`), CMake build system, batch zone processing for grid cells.

**Phase 6 -- Performance:**
Environment variable management, device settings, background task optimisation, JNI call optimisation, coroutine support.

**Phase 7 -- Detection Improvement (current):**
Full-frame preprocessing pipeline (replacing zone-based), Teachable Machine model support (replacing YOLO), animated classification overlay, temporal smoothing, dataset audit script, 38 unit tests.

---

## 21. Known Issues and Legacy Code

### 21.1 Legacy: NmsProcessor

`lib/services/nms_processor.dart` (143 lines) contains Non-Maximum Suppression logic and YOLO output parsing from the earlier object-detection pipeline. It is **no longer called** by the current TM classification pipeline but still compiles and has passing tests. It can be safely removed.

### 21.2 Typo: `asstes/` Directory

The assets directory is named `asstes/images/` instead of `assets/images/`. This affects the logo path in `pubspec.yaml` for `flutter_launcher_icons`. The app functions correctly despite this typo (the icon was already generated).

### 21.3 Supabase Placeholder Keys

`lib/shared/constants.dart` contains placeholder values:
```dart
static const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL', defaultValue: 'https://YOUR_PROJECT_ID.supabase.co');
static const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY', defaultValue: 'YOUR_ANON_KEY');
```

These must be replaced via `--dart-define` at build time or by editing the defaults for Supabase features to work.

### 21.4 PreprocessResult Padding Fields

`PreprocessResult.padLeft` and `PreprocessResult.padTop` are always `0` for TM models (simple resize, no letterbox padding). The `scale` field is computed but not used downstream. These fields are retained for API compatibility with the native preprocessing path which still computes them.

### 21.5 C++ LSP False Positives

`yolo_preprocess.cpp` shows IDE errors (`jni.h not found`, `JNIEXPORT unknown`). These are **false positives** from the language server not being configured for the Android NDK include paths. The file compiles correctly through the Gradle/CMake/NDK build chain.

### 21.6 Grid Mapping with Full-Frame Classification

Since TM classification returns a full-frame bounding box, the grid position is always `(0, 0)` (frame center). The grid overlay still renders and highlights this cell, but the spatial positioning is not meaningful for classification -- it only becomes useful if the camera is mounted directly above the sorting area (top-down view), where "object in frame" = "object at center".

---

## Constants Reference

All tuneable pipeline values are centralised in `lib/utils/detection_constants.dart`:

| Constant | Value | Purpose |
|----------|-------|---------|
| `kConfidenceThreshold` | 0.40 | Minimum confidence to accept a classification |
| `kNmsIouThreshold` | 0.45 | IoU threshold for NMS (legacy, unused) |
| `kBlurSkipThreshold` | 100.0 | Laplacian variance below this = blurry frame |
| `kInputSize` | 224 | Model input dimensions (224x224 for TM) |
| `kSmootherWindowSize` | 5 | Number of frames in temporal smoothing window |
| `kMaxFpsMs` | 66 | Minimum ms between inferences (~15 FPS) |
| `kSmootherMatchIou` | 0.3 | IoU threshold for detection matching across frames |
| `kSmootherMinAppearances` | 2 | Minimum frames a detection must appear in to be emitted |

Note: `AppConfig.confidenceThreshold` (default 0.50, user-adjustable) is the runtime threshold used by `DetectionScreen`. The `kConfidenceThreshold` constant (0.40) is used by `DetectionService` as a pre-filter before smoothing.
