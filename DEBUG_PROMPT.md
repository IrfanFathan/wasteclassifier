# WASTO Tracker — Debug & Performance Optimization Prompt

Use this document as a reference when debugging crashes or performance issues,
or paste it to an AI assistant to get context-aware help.

---

## Project Context

- **Framework**: Flutter (Dart SDK ^3.10.4)
- **Platform target**: Android (primary), minSdk 24, targetSdk 36
- **State management**: Riverpod 3
- **Backend**: Supabase (DB + Storage)
- **ML**: TFLite (`tflite_flutter ^0.12.0`) — 3×3 grid zone inference per frame
- **Native layer**: C++17 JNI via NDK (OpenCV optional) — `libyolo_preprocess.so`
- **Background**: `flutter_foreground_task` (2-min GPS ping) + `workmanager` (15-min fallback)
- **Camera**: `camera ^0.10.5+9`, YUV420, `ResolutionPreset.high`

---

## Known Crash Risks

### 1. Silent model-load failure (detection_screen.dart:171–186)

`_loadModel` catches all exceptions and only prints to debug console.
If the model file is missing or corrupted, `_interpreter` stays null and
`_modelReady` stays false — but no error UI is shown. The camera stream
starts, frames arrive, but inference is silently skipped forever.

**How to reproduce**: Delete or rename the `.tflite` model file and launch.
**Debug check**: Add a `setState(() => _cameraError = 'Model load failed: $e')`
inside the catch block so the user sees an actionable error.

---

### 2. Overlapping GPS requests every second (detection_screen.dart:470–496)

`_onSecondTick` fires a `Timer.periodic` every 1 second and calls
`_updateGpsStatus()`, which calls `Geolocator.getCurrentPosition()` with a
**2-second timeout**. This means a new GPS request is started before the
previous one resolves — creating a permanently overlapping async queue.

Each completion also calls `setState`, triggering a rebuild every 1–2 seconds
regardless of whether the GPS status actually changed.

**Crash risk on low-spec**: On devices with slow GPS hardware the OS
location provider queue fills up, causing `TimeoutException` spam and
`setState` calls on a potentially unmounted widget.

**Debug check**: Add a boolean guard `_gpsRefreshing` and skip the call if
already in-flight. Only call `_updateGpsStatus` every 5 ticks.

```
// Quick guard pattern:
bool _gpsRefreshing = false;

Future<void> _updateGpsStatus() async {
  if (_gpsRefreshing) return;
  _gpsRefreshing = true;
  try { ... } finally { _gpsRefreshing = false; }
}
```

---

### 3. Fire-and-forget detection save with SharedPreferences read (detection_screen.dart:511–554)

`_maybeSaveDetection` wraps its body in `Future(() async {...})` — a
fire-and-forget that has no error boundary beyond a single `debugPrint`.
Inside it calls `SharedPreferences.getInstance()` on every save, which
creates a new async call chain even though the instance is already cached
after first access.

If `mounted` becomes false between the `Future` being scheduled and it
resolving, `ScaffoldMessenger.of(context)` on line 543 will throw a
`FlutterError: Looking up a deactivated widget's ancestor`.

**Debug check**: Guard `ScaffoldMessenger` with `if (!mounted) return;`
immediately before the call (it already exists but is one level above the
`catch`—move it inside the try block before the SnackBar call).

---

### 4. No retry / no error state for camera init (detection_screen.dart:190–234)

`_initCamera` sets `_cameraError` on failure but provides no retry mechanism
in the UI. On low-spec devices, the camera HAL may not be ready at cold-start
and returns a transient `CameraException`. The user is left on a black screen
with no way to recover without restarting the app.

**Debug check**: Add a "Retry" button in the camera error UI widget that calls
`_initCamera()` again.

---

### 5. `Interpreter.fromFile` called on the main isolate (detection_screen.dart:174)

`Interpreter.fromFile` loads and parses the `.tflite` flatbuffer synchronously
on whichever isolate calls it. Since `_loadModel` is `await`ed inside
`_initialize` on the UI isolate, a large model file will jank the UI for
hundreds of milliseconds on first load.

**Debug check**: Wrap inside `compute()` or a manual `Isolate.run()` to move
the disk read + parse off the UI thread.

---

## Performance Issues (Low-Spec Devices)

### P1 — Camera resolution too high (detection_screen.dart:205–210)

```dart
// Current — produces 1280×720 YUV frames (~2.6 MB each)
ResolutionPreset.high
```

On a low-spec device (1–2 GB RAM, Cortex-A53) this means every 300ms you
allocate and GC a 2.6 MB byte buffer, plus 9 sub-images and 9 Float32 tensors
of 224×224×3×4 bytes (~540 KB each = 4.9 MB total per inference cycle).

**Fix**: Use `ResolutionPreset.medium` (640×480, ~460 KB) for the image stream.
The model only needs 224×224 input anyway — the extra pixels are discarded
after crop+resize.

---

### P2 — 9 TFLite inferences per frame (detection_screen.dart:280–304)

The 3×3 grid runs `_interpreter!.run(...)` nine times in a tight synchronous
loop. On a low-spec CPU this can take 300–900ms per cycle — longer than the
throttle window itself, causing `_isProcessing` to be true permanently and
effectively freezing inference.

**Fix options** (pick one based on accuracy requirement):

- Use the existing `scanHorizontalZonesAsync` (3 zones) instead of
  `scanGridZonesAsync` (9 zones) to cut inferences by 66%.
- Run only the center zone (1 inference) as a fast path; fall back to 9-zone
  only when center confidence is below a higher threshold.

---

### P3 — Full-frame pixel-by-pixel YUV→RGB in Dart (image_processor.dart:45–62)

When the native OpenCV library is unavailable (no `opencv.sdk.path` in
`local.properties`), `_scanGridZonesInIsolate` iterates over every pixel of
the full camera frame:

```
// 1280×720 = 921,600 iterations, each doing 3 float multiplications
for (int py = 0; py < height; py++) {
  for (int px = 0; px < width; px++) { ... }
}
```

Although this runs in a `compute()` isolate, it still takes 200–400ms on a
slow core-A53, leaving the main isolate waiting.

**Fix**: Provide the OpenCV NDK SDK path in `android/local.properties` so the
native path is used, OR reduce the camera resolution to medium (P1 fix above)
which cuts iteration count by 75%.

```properties
# android/local.properties
opencv.sdk.path=/path/to/OpenCV-android-sdk
```

---

### P4 — Pulse animation running continuously (detection_screen.dart:138–143)

```dart
_pulseController = AnimationController(duration: Duration(milliseconds: 900))
  ..repeat(reverse: true);
```

An `AnimationController` that runs `repeat()` schedules a vsync callback every
frame (60fps = 16ms). On a low-spec device already busy with camera frames and
inference, this adds a vsync callback that rebuilds the animated widget 60
times per second.

**Fix**: Pause the animation controller when `_state == DetectionState.waiting`
and resume it only when a detection becomes active.

---

### P5 — `setState` every second unconditionally (detection_screen.dart:472–474)

```dart
void _onSecondTick(Timer _) {
  if (!mounted) return;
  setState(() {           // ← always rebuilds the full screen every second
    _pingCountdownSec = ...;
  });
}
```

Even when nothing visually changes (e.g., the countdown is not shown on screen),
the entire `DetectionScreen` widget tree is rebuilt every second. On a low-spec
device this compounds with inference rebuilds.

**Fix**: Extract the countdown display into a separate `StatefulWidget` with its
own `setState`, isolating the rebuild to only that widget.

---

## Debugging Workflow

### Step 1 — Profile before guessing

```bash
# Never use debug mode for performance profiling
flutter run --profile

# Then open DevTools
flutter pub global activate devtools
flutter pub global run devtools
```

In DevTools → **Performance** tab:

- Look for frames exceeding 16ms (red bars = jank)
- Check the **CPU profiler** for the hottest call stacks

---

### Step 2 — Enable detailed logging for the inference pipeline

Add this at the top of `_runInference` temporarily:

```dart
final t0 = Stopwatch()..start();
final zones = await ImageProcessor.scanGridZonesAsync(image);
debugPrint('scanGridZones: ${t0.elapsedMilliseconds}ms');
t0.reset();
// ... run inferences ...
debugPrint('9x inference: ${t0.elapsedMilliseconds}ms');
```

This will show exactly how much time is spent in preprocessing vs. inference.

---

### Step 3 — Check for memory pressure

On low-spec devices, OOM kills often look like crashes with no Dart stack trace.

```bash
# Monitor memory during a run
adb shell dumpsys meminfo com.yourpackage.wasteclassifier
```

Watch for `NativeHeap` growing unboundedly — this indicates the native YUV
buffers or TFLite tensors are not being released between frames.

---

### Step 4 — Verify native library is loaded

```bash
adb logcat | grep -i "opencv\|yolo_preprocess\|libc"
```

If you see `dlopen failed` or `UnsatisfiedLinkError`, the native preprocessing
is falling back to Dart on every frame (P3 above is active).

---

### Step 5 — Check for GPS-related ANR

```bash
adb logcat | grep -i "anr\|geolocator\|location"
```

If GPS requests are stacking up, you will see `Input dispatching timed out`
or `Broadcast of Intent ... took too long` in the ANR trace.

---

## Quick Optimization Checklist for Low-Spec Devices

| #   | Location                    | Change                                                                | Expected gain                                 |
| --- | --------------------------- | --------------------------------------------------------------------- | --------------------------------------------- |
| 1   | `detection_screen.dart:207` | `ResolutionPreset.high` → `medium`                                    | 75% less frame memory                         |
| 2   | `detection_screen.dart:93`  | `_frameThrottleMs = 300` → `600`                                      | 50% fewer inference cycles                    |
| 3   | `detection_screen.dart:269` | `scanGridZonesAsync` (9 zones) → `scanHorizontalZonesAsync` (3 zones) | 66% fewer TFLite calls                        |
| 4   | `detection_screen.dart:176` | `threads = 2` → `threads = 1`                                         | Avoids context-switch overhead on single-core |
| 5   | `detection_screen.dart:475` | GPS every tick → GPS every 5 ticks                                    | 80% fewer GPS requests                        |
| 6   | `detection_screen.dart:138` | Pause pulse animation when not detecting                              | Saves 60 vsync callbacks/sec                  |
| 7   | `android/local.properties`  | Set `opencv.sdk.path`                                                 | Native YUV path: ~10ms vs ~300ms              |

---

## Files Reference

| File                                               | Role                                      |
| -------------------------------------------------- | ----------------------------------------- |
| `lib/screens/detection_screen.dart`                | Main inference + camera loop (1268 lines) |
| `lib/utils/image_processor.dart`                   | YUV→RGB, zone crop, tensor build          |
| `lib/features/detection/detection_repository.dart` | Supabase upload + insert                  |
| `lib/features/location/location_repository.dart`   | GPS ping insert                           |
| `lib/core/background_service.dart`                 | Foreground service task handler           |
| `android/app/src/main/cpp/yolo_preprocess.cpp`     | Native OpenCV JNI                         |
| `android/app/src/main/cpp/CMakeLists.txt`          | NDK build config                          |
