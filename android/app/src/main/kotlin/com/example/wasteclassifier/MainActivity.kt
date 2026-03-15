package com.example.wasteclassifier

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "opencv_pipeline"
    }

    // Coroutine scope tied to this Activity's lifecycle.
    // SupervisorJob so one failed JNI call doesn't cancel in-flight siblings.
    private val scope = CoroutineScope(SupervisorJob())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── is_opencv_available ──────────────────────────────
                    // Synchronous flag read — no JNI image work involved.
                    "is_opencv_available" -> {
                        result.success(OpenCVHelper.isAvailable)
                    }

                    // ── preprocess_zone ──────────────────────────────────
                    // Arguments (all required):
                    //   y_plane        : ByteArray  — Y luma plane bytes
                    //   u_plane        : ByteArray  — U chroma plane bytes
                    //   v_plane        : ByteArray  — V chroma plane bytes
                    //   y_row_stride   : Int
                    //   uv_row_stride  : Int
                    //   uv_pixel_stride: Int
                    //   width          : Int        — full frame width
                    //   height         : Int        — full frame height
                    //   zone_x         : Int        — zone left edge
                    //   zone_y         : Int        — zone top edge
                    //   zone_w         : Int        — zone width
                    //   zone_h         : Int        — zone height
                    //   target_size    : Int        — output side (e.g. 224)
                    //
                    // Returns Float32List on success, error otherwise.
                    "preprocess_zone" -> {
                        if (!OpenCVHelper.isAvailable) {
                            result.error(
                                "OPENCV_UNAVAILABLE",
                                "Native yolo_preprocess library not loaded",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as Map<String, Any>

                        // Heavy JNI work on a background thread.
                        scope.launch(Dispatchers.Default) {
                            try {
                                val floats = OpenCVHelper.preprocessZone(
                                    yPlane          = args["y_plane"]          as ByteArray,
                                    uPlane          = args["u_plane"]          as ByteArray,
                                    vPlane          = args["v_plane"]          as ByteArray,
                                    yRowStride      = args["y_row_stride"]     as Int,
                                    uvRowStride     = args["uv_row_stride"]    as Int,
                                    uvPixelStride   = args["uv_pixel_stride"]  as Int,
                                    frameWidth      = args["width"]            as Int,
                                    frameHeight     = args["height"]           as Int,
                                    zoneX           = args["zone_x"]           as Int,
                                    zoneY           = args["zone_y"]           as Int,
                                    zoneW           = args["zone_w"]           as Int,
                                    zoneH           = args["zone_h"]           as Int,
                                    targetSize      = args["target_size"]      as Int,
                                )
                                // Reply must be issued on the main/platform thread.
                                withContext(Dispatchers.Main) {
                                    if (floats != null) {
                                        result.success(floats)
                                    } else {
                                        result.error(
                                            "PREPROCESS_FAILED",
                                            "Native preprocessZone returned null",
                                            null
                                        )
                                    }
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("PREPROCESS_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    // ── preprocess_horizontal_zones ──────────────────────
                    // Batch variant: processes left / centre / right thirds
                    // of the frame in one JNI call, avoiding 3× plane transfer.
                    //
                    // Arguments:
                    //   y_plane / u_plane / v_plane : ByteArray
                    //   y_row_stride / uv_row_stride / uv_pixel_stride : Int
                    //   width / height  : Int
                    //   target_size     : Int
                    //
                    // Returns Float32List of length 3 × target² × 3.
                    "preprocess_horizontal_zones" -> {
                        if (!OpenCVHelper.isAvailable) {
                            result.error(
                                "OPENCV_UNAVAILABLE",
                                "Native yolo_preprocess library not loaded",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as Map<String, Any>

                        scope.launch(Dispatchers.Default) {
                            try {
                                val floats = OpenCVHelper.preprocessHorizontalZones(
                                    yPlane          = args["y_plane"]         as ByteArray,
                                    uPlane          = args["u_plane"]         as ByteArray,
                                    vPlane          = args["v_plane"]         as ByteArray,
                                    yRowStride      = args["y_row_stride"]    as Int,
                                    uvRowStride     = args["uv_row_stride"]   as Int,
                                    uvPixelStride   = args["uv_pixel_stride"] as Int,
                                    frameWidth      = args["width"]           as Int,
                                    frameHeight     = args["height"]          as Int,
                                    targetSize      = args["target_size"]     as Int,
                                )
                                withContext(Dispatchers.Main) {
                                    if (floats != null) {
                                        result.success(floats)
                                    } else {
                                        result.error(
                                            "PREPROCESS_FAILED",
                                            "Native preprocessHorizontalZones returned null",
                                            null
                                        )
                                    }
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("PREPROCESS_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    // ── preprocess_grid_zones ─────────────────────────────
                    // Batch variant: processes a cols×rows grid of zones in
                    // one JNI call — single YUV decode, all zones in one pass.
                    //
                    // Arguments:
                    //   y_plane / u_plane / v_plane : ByteArray
                    //   y_row_stride / uv_row_stride / uv_pixel_stride : Int
                    //   width / height : Int
                    //   cols / rows    : Int
                    //   target_size    : Int
                    //
                    // Returns Float32List of length (cols*rows) × target² × 3.
                    "preprocess_grid_zones" -> {
                        if (!OpenCVHelper.isAvailable) {
                            result.error(
                                "OPENCV_UNAVAILABLE",
                                "Native yolo_preprocess library not loaded",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        @Suppress("UNCHECKED_CAST")
                        val args = call.arguments as Map<String, Any>

                        scope.launch(Dispatchers.Default) {
                            try {
                                val floats = OpenCVHelper.preprocessGridZones(
                                    yPlane          = args["y_plane"]          as ByteArray,
                                    uPlane          = args["u_plane"]          as ByteArray,
                                    vPlane          = args["v_plane"]          as ByteArray,
                                    yRowStride      = args["y_row_stride"]     as Int,
                                    uvRowStride     = args["uv_row_stride"]    as Int,
                                    uvPixelStride   = args["uv_pixel_stride"]  as Int,
                                    frameWidth      = args["width"]            as Int,
                                    frameHeight     = args["height"]           as Int,
                                    cols            = args["cols"]             as Int,
                                    rows            = args["rows"]             as Int,
                                    targetSize      = args["target_size"]      as Int,
                                )
                                withContext(Dispatchers.Main) {
                                    if (floats != null) {
                                        result.success(floats)
                                    } else {
                                        result.error(
                                            "PREPROCESS_FAILED",
                                            "Native preprocessGridZones returned null",
                                            null
                                        )
                                    }
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("PREPROCESS_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
