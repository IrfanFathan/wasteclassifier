# 📱 Waste Classifier – Application Documentation

> A real-time waste classification app for Android that uses your own **Google Teachable Machine** TFLite model to identify waste items via the device camera and tell you which bin they belong to.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture & Project Structure](#2-architecture--project-structure)
3. [Dependencies](#3-dependencies)
4. [Data Models](#4-data-models)
5. [Utility Classes](#5-utility-classes)
6. [Screen-by-Screen Walkthrough](#6-screen-by-screen-walkthrough)
7. [App Flow Diagram](#7-app-flow-diagram)
8. [Configuration & Persistence](#8-configuration--persistence)
9. [AI Inference Pipeline](#9-ai-inference-pipeline)
10. [Theme & Design System](#10-theme--design-system)
11. [How to Use the App](#11-how-to-use-the-app)

---

## 1. Overview

**Waste Classifier** is a mobile application built with **Flutter** that turns your phone's camera into a smart waste detector. It uses a TensorFlow Lite model you train yourself (via Google's [Teachable Machine](https://teachablemachine.withgoogle.com/)) to classify objects seen by the camera and tell you in real time which rubbish bin the object belongs to.

### Key Features
| Feature | Description |
|---|---|
| 🤖 On-device AI | TFLite inference runs entirely on your phone — no internet required |
| 📦 Model upload | Upload your own `.tflite` + `labels.txt` (or a `.zip`) |
| 🗑️ Custom bins | Configure any number of bins (e.g. Plastic, Metal, Paper) with custom names, emojis and colors |
| 🏷️ Label mapping | Map each waste class label to a specific bin |
| 🎥 Real-time detection | Live camera feed with instant classification results |
| 💾 Persistent config | All settings persist across app restarts |

---

## 2. Architecture & Project Structure

```
lib/
├── main.dart                   # App entry point, global ThemeData
│
├── models/
│   ├── app_config.dart         # Main config data class (bins + thresholds)
│   └── bin_category.dart       # A single bin definition (name, emoji, color, labels)
│
├── screens/
│   ├── upload_screen.dart      # Step 1 – Upload model files
│   ├── bin_setup_screen.dart   # Step 2 – Configure bins and label mappings
│   └── detection_screen.dart   # Step 3 – Live camera detection
│
└── utils/
    ├── config_manager.dart     # SharedPreferences read/write for config
    ├── model_manager.dart      # File I/O for model.tflite and labels.txt
    └── image_processor.dart    # YUV420 → RGB → normalized Float32 tensor
```

The app follows a **3-step linear flow**:

```
Upload Screen  ──►  Bin Setup Screen  ──►  Detection Screen
   (files)            (categories)           (live camera)
```

---

## 3. Dependencies

| Package | Version | Purpose |
|---|---|---|
| `camera` | ^0.10.5+9 | Access device camera for live preview and image stream |
| `tflite_flutter` | ^0.12.0 | Run TensorFlow Lite model inference on device |
| `image` | ^4.1.7 | Convert and resize raw camera frames |
| `file_picker` | ^8.0.0+1 | Let user pick files (`.tflite`, `.txt`, `.zip`) from device storage |
| `path_provider` | ^2.1.2 | Get the app's persistent document directory |
| `path` | ^1.9.0 | Cross-platform path manipulation |
| `shared_preferences` | ^2.2.2 | Persist configuration (bins, labels, thresholds) across launches |
| `flutter_colorpicker` | ^1.0.3 | Color picker widget for bin color selection |
| `archive` | ^4.0.0 | Parse and extract `.zip` files |
| `google_fonts` | ^8.0.2 | Inter font for clean typography |

---

## 4. Data Models

### `BinCategory` (`models/bin_category.dart`)

Represents a single waste bin category.

```dart
class BinCategory {
  String id;           // Unique ID: e.g. "bin_1708123456789"
  String name;         // Display name: e.g. "Plastic Bin"
  String emoji;        // Visual emoji: e.g. "♻️"
  int colorHex;        // ARGB int color for color dot and border
  List<String> mappedLabels;  // Labels assigned to this bin, e.g. ["Plastic Bottle", "Plastic Bag"]
}
```

**Serialization**: `toJson()` / `fromJson()` for SharedPreferences storage.

---

### `AppConfig` (`models/app_config.dart`)

Holds the complete application configuration.

```dart
class AppConfig {
  List<BinCategory> bins;        // All configured bins
  double confidenceThreshold;   // Default: 0.85 (85%) – minimum score to trigger a detection
  List<String> nothingLabels;   // Labels to IGNORE (e.g. "Background", "Nothing")
}
```

**Serialization**: `toJsonString()` / `fromJsonString()` for full JSON persistence.

---

## 5. Utility Classes

### `ConfigManager` (`utils/config_manager.dart`)

Handles all **SharedPreferences** read/write operations.

| Method | Description |
|---|---|
| `loadConfig()` | Reads `AppConfig` from JSON stored in SharedPreferences. Returns `null` if no config saved. |
| `saveConfig(config)` | Serializes `AppConfig` to JSON string and writes to SharedPreferences. |
| `loadLabels()` | Reads the labels list (stored as a JSON array string). |
| `saveLabels(labels)` | Writes the labels list as a JSON string. |
| `isModelLoaded()` | Returns boolean flag indicating if model files exist. |
| `setModelLoaded(bool)` | Sets the boolean flag in preferences. |
| `clearAll()` | Removes all three keys (config, labels, model flag) from SharedPreferences – used when changing the model. |

**Storage Keys:**
```
app_config     →  Full AppConfig JSON string
labels_list    →  JSON array of label strings
model_loaded   →  Boolean flag
```

---

### `ModelManager` (`utils/model_manager.dart`)

Handles **file system operations** for the TFLite model and labels file.

| Method | Description |
|---|---|
| `getModelPath()` | Returns absolute path to `model.tflite` in Documents directory. |
| `getLabelsPath()` | Returns absolute path to `labels.txt` in Documents directory. |
| `modelFilesExist()` | Returns `true` if both `model.tflite` and `labels.txt` exist on disk. |
| `saveModelFile(src)` | Copies a `.tflite` file from the picked path to the Documents directory. |
| `saveLabelsFile(src)` | Copies a `labels.txt` file from the picked path to the Documents directory. |
| `extractZip(zipPath)` | Reads a `.zip`, finds and extracts `model.tflite` and `labels.txt` automatically. Returns a `ZipExtractResult`. |
| `parseLabelsFile()` | Reads `labels.txt` and strips the leading index numbers (e.g. `"0 Plastic Bottle"` → `"Plastic Bottle"`). |
| `deleteModelFiles()` | Deletes both model and labels files from disk (when changing model). |

**Path**: Both files are stored in `getApplicationDocumentsDirectory()` which persists across app restarts.

---

### `ImageProcessor` (`utils/image_processor.dart`)

Converts raw camera frames from YUV420 format into a normalized float tensor for TFLite inference.

**Input size**: 224×224 pixels (standard Teachable Machine input).

**Pipeline**:

```
CameraImage (YUV420)
       │
       ▼
  _convertYUV420toRGB()
  ┌─────────────────────────────────┐
  │  For each pixel (x, y):        │
  │    Y, U, V values extracted    │
  │    Converted to R, G, B        │
  │    Clamped to [0, 255]         │
  └─────────────────────────────────┘
       │
       ▼
  img.copyResize() → 224×224
       │
       ▼
  _normalizeImage()
  ┌─────────────────────────────────┐
  │  For each pixel:               │
  │    r, g, b divided by 255.0    │
  │    Values in range [0.0, 1.0]  │
  └─────────────────────────────────┘
       │
       ▼
  Float32List[150528]  (1 × 224 × 224 × 3)
```

---

## 6. Screen-by-Screen Walkthrough

### Screen 1: App Startup (`_AppStartup` in `main.dart`)

Shown for **< 1 second** while the app checks the device state.

**Logic:**
```
isModelLoaded()
   ├── false → modelFilesExist()
   │              ├── false → Go to UploadScreen
   │              └── true  → fallthrough
   │
   └── true
          │
          loadConfig()
          ├── null / empty bins → Go to BinSetupScreen
          └── valid config      → Go to DetectionScreen
```

**UI**: Centered `♻️` emoji, "Waste Classifier" title, circular progress indicator.

---

### Screen 2: Upload Screen (`screens/upload_screen.dart`)

Allows the user to provide the machine learning model to the app.

#### 2.1 Two Upload Modes (Tabs)

**Tab 1 – Upload ZIP** *(Recommended)*
- User picks any `.zip` file from their device
- App uses `ModelManager.extractZip()` to find `model.tflite` and `labels.txt` inside
- If both are found, they are saved to Documents directory
- Status icon animates (success ✓ or error ✗)
- Teachable Machine export steps shown inline as a hint card

**Tab 2 – Separate Files**
- Two upload cards displayed – one for `model.tflite`, one for `labels.txt`
- Each has its own upload state: `idle` → `loading` → `success` / `error`
- Both must be `success` to enable the Continue button

#### 2.2 File Status Chips
When files already exist from a previous session, two small chips appear at the top showing `model.tflite ✓` and `labels.txt ✓`.

#### 2.3 Continue Button
Appears only when both files are confirmed present. Tapping navigates to `BinSetupScreen` and passes the parsed labels list.

#### 2.4 Upload States (`_UploadState`)
```dart
enum _UploadState { idle, loading, success, error }
```

#### 2.5 State Management
All upload states are managed inside `_UploadScreenState`:
```
_modelExists       → bool
_labelsExist       → bool
_zipState          → _UploadState
_zipStatus         → String (status message)
_modelState        → _UploadState
_labelsState       → _UploadState
_modelStatus       → String
_labelsStatus      → String
```

---

### Screen 3: Bin Setup (`screens/bin_setup_screen.dart`)

The configuration screen where the user defines their bins and maps model labels to them.

#### 3.1 Section A – Your Bins

- **Empty state**: Shows an example hints card with example bin configurations.
- **Bin Tile**: Each created bin shows its emoji, name, color dot, edit button, and delete button.
- **Add New Bin**: Opens a bottom sheet `_showAddEditBinSheet()`.

#### 3.2 Add/Edit Bin Bottom Sheet

Fields:
| Field | Description |
|---|---|
| Bin Name | Text input, e.g. "Plastic Bin" |
| Emoji | Single-char emoji picker input, e.g. "♻️" |
| Bin Color | Full color picker (`flutter_colorpicker`) |

Wrapped in `SingleChildScrollView` so the keyboard never causes overflow.

On save, a new `BinCategory` is created with a timestamp-based unique ID:
```dart
String _generateBinId() => 'bin_${DateTime.now().millisecondsSinceEpoch}';
```

#### 3.3 Section B – Map Labels to Bins

Each label from `labels.txt` gets a `DropdownButton` with three choices:
| Option | Effect |
|---|---|
| Leave Unmapped | Label is ignored even if detected |
| Nothing / Skip | Treated as background/nothing, resets detection to waiting |
| [Bin Name] | Detection of this label triggers that bin's card |

An indicator dot previews the assigned bin color for quick visual scanning.

#### 3.4 Section C – Detection Sensitivity

A `Slider` widget lets the user set the minimum confidence threshold from **50% to 99%**.
- Only detections scoring above this threshold will trigger the result display.
- Default: 85%.

#### 3.5 Save & Navigate

`_saveAndNavigate()` validates:
1. At least one bin created
2. At least one label mapped to a bin

Then:
1. Builds `finalBins` (bins with their `mappedLabels` populated)
2. Collects `nothingLabels`
3. Creates `AppConfig` and writes it via `ConfigManager.saveConfig()`
4. Navigates to `DetectionScreen` via `pushReplacement`

---

### Screen 4: Detection Screen (`screens/detection_screen.dart`)

The main real-time camera view with live waste classification.

#### 4.1 Initialization Sequence

```
_initialize()
  ├── _loadConfig()   → Loads AppConfig + labels from SharedPreferences
  ├── _loadModel()    → Creates tflite_flutter Interpreter from model.tflite on disk
  └── _initCamera()   → availableCameras() → prefers back camera
                         → CameraController(ResolutionPreset.medium, YUV420)
                         → startImageStream(_onCameraFrame)
```

#### 4.2 Camera Image Stream

Every camera frame calls `_onCameraFrame(CameraImage)`:
- Skips frame if `_isProcessing` is `true` (prevents queue build-up)
- Otherwise sets `_isProcessing = true` and calls `_runInference(image)`

#### 4.3 Inference Pipeline

```
_runInference(CameraImage)
  │
  ├── ImageProcessor.processImage(image)
  │     Returns Float32List[150528]
  │
  ├── Reinterpret as Uint8List (raw bytes for tflite_flutter 0.12.x)
  │
  ├── Create output buffer [1 × numClasses]
  │
  ├── _interpreter!.run(inputBytes, output)
  │
  ├── Find argmax (label with highest probability)
  │
  └── _processResult(label, maxProb)
```

#### 4.4 Result Processing (`_processResult`)

```
confidence < threshold?
  └── Set state = waiting

label in nothingLabels?
  └── Set state = waiting

label in any bin's mappedLabels?
  ├── yes → Set state = detected, _detectedBin = matched bin
  └── no  → Set state = unmapped
```

#### 4.5 Detection States

```dart
enum DetectionState { waiting, detected, unmapped }
```

| State | Display |
|---|---|
| `waiting` | "Point camera at an object" card |
| `detected` | Large label + confidence % + bin card |
| `unmapped` | Warning card + orange label name |

#### 4.6 UI Layout (Stack)

```
Stack (StackFit.expand)
 ├── [1] Camera preview (AspectRatio 4:3, centered in black Container)
 ├── [2] 3×3 Grid overlay (CustomPaint _GridPainter)
 ├── [3] Center reticle (4-corner brackets, animated on detect)
 ├── [4] Top floating bar (Settings | Title | Change Model)
 ├── [5] Floating result card (animated, 200px from bottom)
 └── [6] Bottom shutter deck (gradient + mechanical circle button)
```

#### 4.7 Navigation Actions

| Button | Action |
|---|---|
| ⚙️ Settings (tune icon) | Stops image stream → Opens `BinSetupScreen` with existing config → Resumes stream on return |
| ↔️ Change Model | Shows confirmation dialog → Deletes model files + clears config → Returns to `UploadScreen` |

---

## 7. App Flow Diagram

```
┌──────────────────────────────────────────────────────────┐
│                        App Start                         │
│                     _AppStartup                          │
│                                                          │
│  Model files exist?                                      │
│  ─────────────────                                       │
│     NO  → UploadScreen                                   │
│     YES → Config exists?                                 │
│              NO  → BinSetupScreen                        │
│              YES → DetectionScreen  ◄────────────────┐  │
└──────────────────────────────────────────────────────|───┘
                                                       │
                                                       │
  UploadScreen                                         │
  ────────────                                         │
  Upload ZIP or separate files                         │
  Both confirmed present?                              │
        │                                              │
        ▼                                              │
  BinSetupScreen                                       │
  ─────────────                                        │
  1. Create bins  (name, emoji, color)                 │
  2. Map labels to bins                                │
  3. Set confidence threshold                          │
  4. Save & Continue ──►  DetectionScreen ─────────────┘

  DetectionScreen
  ───────────────
  Live camera → Frame → Inference → Result
        ↑                                ↓
        └────────────────────────────────┘  (continuous loop)

  Settings button → BinSetupScreen (edit mode) → Back to Detection
  Change Model   → UploadScreen (fresh start)
```

---

## 8. Configuration & Persistence

All data is saved in `SharedPreferences` and survives app restarts and device reboots.

| Key | Type | Content |
|---|---|---|
| `app_config` | `String` | Full JSON of bins + threshold + nothingLabels |
| `labels_list` | `String` | JSON array of label strings |
| `model_loaded` | `bool` | Whether model files are available |

Model files (`model.tflite`, `labels.txt`) are stored in `getApplicationDocumentsDirectory()` which is sandboxed to the app and not cleared on restart.

**When the user presses "Change Model":**
1. `ModelManager.deleteModelFiles()` – removes both files from disk
2. `ConfigManager.clearAll()` – removes all three SharedPreference keys
3. App navigates back to `UploadScreen`

---

## 9. AI Inference Pipeline

### Model Requirements

The app is designed for models exported from **Google Teachable Machine**:
- Format: **TensorFlow Lite – Floating Point**
- Input shape: `[1, 224, 224, 3]` (batch=1, height=224, width=224, channels=3)
- Output shape: `[1, numClasses]` (probability per class)
- Normalization: pixel values `[0.0, 1.0]`

### Inference Call

The app uses `tflite_flutter ^0.12.x`. Due to shape matching requirements in this version, the normalized `Float32List` is reinterpreted as `Uint8List` (raw bytes) before passing to `_interpreter!.run()`. This avoids a shape mismatch error where tflite_flutter would try to resize a flat list.

```dart
final inputFlat = ImageProcessor.processImage(image);     // Float32List
final inputBytes = inputFlat.buffer.asUint8List();         // Uint8List (raw bytes)
final output = [List<double>.filled(numClasses, 0.0)];     // [1, n]
_interpreter!.run(inputBytes, output);
```

### Label Parsing

`labels.txt` from Teachable Machine uses the format:
```
0 Plastic Bottle
1 Aluminium Can
2 Background
```
`ModelManager.parseLabelsFile()` strips the leading index and returns just `["Plastic Bottle", "Aluminium Can", "Background"]`.

---

## 10. Theme & Design System

The app uses a clean, minimal **Light Theme** with:

| Token | Color | Use |
|---|---|---|
| Scaffold Background | `#F9FAFB` (gray-50) | All screen backgrounds |
| Surface / Card | `#FFFFFF` | Cards, sheets, inputs |
| Primary Text | `#14171A` (charcoal) | Headings, primary labels |
| Secondary Text | `#6B7280` (cool gray) | Subtitles, hints |
| Divider | `#D1D5DB` | Section separators |
| Error | `#C62828` | Danger actions/text |
| Primary Button BG | `#14171A` | ElevatedButton background |
| Primary Button FG | `#FFFFFF` | ElevatedButton text/icon |

**Typography**: `GoogleFonts.inter` at all levels.

| Style | Size | Weight | Use |
|---|---|---|---|
| `headlineMedium` | 26px | w700 | Screen titles |
| `titleMedium` | 18px | w600 | Section headers |
| `bodyLarge` | 16px | w400 | Main body text |
| `bodyMedium` | 14px | w400 | Secondary/hint text |
| `labelSmall` | 12px | w400 | Status footnotes |

---

## 11. How to Use the App

### Step 1: Train Your Model

1. Go to [teachablemachine.withgoogle.com](https://teachablemachine.withgoogle.com/)
2. Create an **Image Project**
3. Add classes (e.g. "Plastic Bottle", "Aluminium Can", "Background")
4. Train the model
5. Click **Export Model → TensorFlow Lite → Floating Point**
6. Download the **`.zip`** file

### Step 2: Upload the Model

1. Open the app → you'll land on the **Upload Screen**
2. On the **Upload ZIP** tab, tap **"Pick .zip File"**
3. Select the downloaded `.zip` from Teachable Machine
4. Wait for the green success confirmation
5. Tap **"Continue → Set Up Bins"**

### Step 3: Set Up Your Bins

1. Tap **"Add New Bin"** to create a bin category
2. Enter a name (e.g. "Plastic Bin"), emoji (e.g. ♻️), and pick a color
3. Repeat for each bin type you have
4. In **"Map Labels to Bins"**, assign each class label to its corresponding bin
5. Mark "Background" / "Nothing" labels as **"Nothing / Skip"**
6. Adjust the **Detection Sensitivity** slider if needed
7. Tap **"✅ Save & Start Detecting"**

### Step 4: Use the Camera

1. Point the camera at a piece of waste
2. The app shows results in real time:
   - **Detected** → Shows the label, confidence %, and which bin to use
   - **Unmapped** → Shows the label with a warning (go to Settings to map it)
   - **Waiting** → Not enough confidence or object is "Nothing"

### Step 5: Returning to Settings

Tap the ⚙️ icon (top-left) to go back to **Bin Setup** and edit your configuration at any time.

### Changing the Model

Tap the ↔️ icon (top-right) and confirm to wipe the current model and start fresh with a new one.

---

*Documentation generated for Waste Classifier v1.0.0+1*
