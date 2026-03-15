// yolo_preprocess.cpp
//
// JNI bridge for fast YUV_420_888 → RGB → crop → resize → Float32 tensor.
//
// When compiled with OpenCV (HAVE_OPENCV defined via CMake), the functions
// perform full native preprocessing.  Without OpenCV they return nullptr so
// the Dart side falls back to the pure-Dart ImageProcessor implementation.

#include <jni.h>
#include <android/log.h>

#define TAG "YoloPreprocess"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

#ifdef HAVE_OPENCV

#include <cmath>
#include <cstring>
#include <vector>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>

// ─── YUV_420_888 → BGR ────────────────────────────────────────────────────
//
// Android YUV_420_888 planes:
//   plane[0] = Y  (one byte per pixel, y_row_stride bytes per row)
//   plane[1] = U  (one byte per pixel pair, semi-planar or planar)
//   plane[2] = V  (same layout as U)
//
// uv_pixel_stride == 2  → interleaved NV12/NV21-style UV
// uv_pixel_stride == 1  → fully planar YUV420p-style

static cv::Mat yuv420_to_bgr(
    const uint8_t *y_data, int y_row_stride,
    const uint8_t *u_data,
    const uint8_t *v_data,
    int uv_row_stride, int uv_pixel_stride,
    int width, int height)
{
    cv::Mat bgr(height, width, CV_8UC3);

    for (int row = 0; row < height; ++row)
    {
        uint8_t *dst = bgr.ptr<uint8_t>(row);
        const uint8_t *y_row = y_data + row * y_row_stride;

        for (int col = 0; col < width; ++col)
        {
            const int uv_idx =
                (row / 2) * uv_row_stride + (col / 2) * uv_pixel_stride;

            const int Y = static_cast<int>(y_row[col]);
            const int U = static_cast<int>(u_data[uv_idx]) - 128;
            const int V = static_cast<int>(v_data[uv_idx]) - 128;

            // Cast the whole expression then round — matches the Dart fallback
            // which uses .round(), ensuring native and Dart paths produce
            // identical RGB values and therefore identical model inputs.
            const int r = static_cast<int>(std::round(Y + 1.402f  * V));
            const int g = static_cast<int>(std::round(Y - 0.344136f * U - 0.714136f * V));
            const int b = static_cast<int>(std::round(Y + 1.772f  * U));

            dst[col * 3 + 0] = static_cast<uint8_t>(std::max(0, std::min(255, b)));
            dst[col * 3 + 1] = static_cast<uint8_t>(std::max(0, std::min(255, g)));
            dst[col * 3 + 2] = static_cast<uint8_t>(std::max(0, std::min(255, r)));
        }
    }

    return bgr;
}

// ─── Helper: pin JNI arrays and return false on failure ──────────────────
struct YuvPlanes
{
    jbyte *y_raw = nullptr;
    jbyte *u_raw = nullptr;
    jbyte *v_raw = nullptr;
    jbyteArray j_y, j_u, j_v;
    JNIEnv *env;

    bool acquire(JNIEnv *e,
                 jbyteArray jy, jbyteArray ju, jbyteArray jv)
    {
        env = e;
        j_y = jy;
        j_u = ju;
        j_v = jv;
        y_raw = env->GetByteArrayElements(jy, nullptr);
        u_raw = env->GetByteArrayElements(ju, nullptr);
        v_raw = env->GetByteArrayElements(jv, nullptr);
        return y_raw && u_raw && v_raw;
    }

    void release()
    {
        if (y_raw)
            env->ReleaseByteArrayElements(j_y, y_raw, JNI_ABORT);
        if (u_raw)
            env->ReleaseByteArrayElements(j_u, u_raw, JNI_ABORT);
        if (v_raw)
            env->ReleaseByteArrayElements(j_v, v_raw, JNI_ABORT);
    }

    const uint8_t *y() const { return reinterpret_cast<const uint8_t *>(y_raw); }
    const uint8_t *u() const { return reinterpret_cast<const uint8_t *>(u_raw); }
    const uint8_t *v() const { return reinterpret_cast<const uint8_t *>(v_raw); }
};

// ─── Helper: zone → Float32 slice ─────────────────────────────────────────
static void zone_to_float32(
    const cv::Mat &full_bgr,
    int zone_x, int zone_y, int zone_w, int zone_h,
    int target_size,
    float *out // caller-allocated, size = target²×3
)
{
    cv::Mat zone_bgr = full_bgr(
                           cv::Rect(zone_x, zone_y, zone_w, zone_h))
                           .clone();

    cv::Mat zone_rgb;
    cv::cvtColor(zone_bgr, zone_rgb, cv::COLOR_BGR2RGB);

    cv::Mat resized;
    cv::resize(zone_rgb, resized,
               cv::Size(target_size, target_size), 0, 0, cv::INTER_LINEAR);

    int idx = 0;
    for (int r = 0; r < target_size; ++r)
    {
        const uint8_t *row_ptr = resized.ptr<uint8_t>(r);
        for (int c = 0; c < target_size; ++c)
        {
            out[idx++] = row_ptr[c * 3 + 0] / 255.0f; // R
            out[idx++] = row_ptr[c * 3 + 1] / 255.0f; // G
            out[idx++] = row_ptr[c * 3 + 2] / 255.0f; // B
        }
    }
}

#endif // HAVE_OPENCV

// ─── JNI entry points ─────────────────────────────────────────────────────

extern "C"
{

    // ── isOpenCVEnabled ───────────────────────────────────────────────────────
    // Returns JNI_TRUE only when compiled with HAVE_OPENCV.
    // Lets the Kotlin side report accurate availability without making a
    // preprocessing call that would fail.
    JNIEXPORT jboolean JNICALL
    Java_com_example_wasteclassifier_OpenCVHelper_isOpenCVEnabled(
        JNIEnv *, jobject /* obj */
    )
    {
#ifdef HAVE_OPENCV
        return JNI_TRUE;
#else
        return JNI_FALSE;
#endif
    }

    // ── preprocessZone ────────────────────────────────────────────────────────
    JNIEXPORT jfloatArray JNICALL
    Java_com_example_wasteclassifier_OpenCVHelper_preprocessZone(
        JNIEnv *env, jobject /* obj */,
        jbyteArray j_y_plane, jbyteArray j_u_plane, jbyteArray j_v_plane,
        jint y_row_stride, jint uv_row_stride, jint uv_pixel_stride,
        jint frame_width, jint frame_height,
        jint zone_x, jint zone_y, jint zone_w, jint zone_h,
        jint target_size)
    {
#ifndef HAVE_OPENCV
        LOGI("preprocessZone: OpenCV not compiled in — returning null");
        return nullptr;
#else
        YuvPlanes planes;
        if (!planes.acquire(env, j_y_plane, j_u_plane, j_v_plane))
        {
            LOGE("preprocessZone: GetByteArrayElements returned null");
            planes.release();
            return nullptr;
        }

        cv::Mat full_bgr = yuv420_to_bgr(
            planes.y(), y_row_stride,
            planes.u(), planes.v(),
            uv_row_stride, uv_pixel_stride,
            frame_width, frame_height);
        planes.release();

        // Clamp zone to frame bounds.
        const int cx = std::max(0, std::min(zone_x, frame_width - 1));
        const int cy = std::max(0, std::min(zone_y, frame_height - 1));
        const int cw = std::max(1, std::min(zone_w, frame_width - cx));
        const int ch = std::max(1, std::min(zone_h, frame_height - cy));

        const int output_len = target_size * target_size * 3;
        jfloatArray j_result = env->NewFloatArray(output_len);
        if (!j_result)
        {
            LOGE("preprocessZone: NewFloatArray failed");
            return nullptr;
        }

        std::vector<float> tensor(output_len);
        zone_to_float32(full_bgr, cx, cy, cw, ch, target_size, tensor.data());

        env->SetFloatArrayRegion(j_result, 0, output_len, tensor.data());
        LOGI("preprocessZone OK: zone=(%d,%d,%d,%d) target=%d", cx, cy, cw, ch, target_size);
        return j_result;
#endif
    }

    // ── preprocessGridZones ───────────────────────────────────────────────────
    //
    // Processes a cols×rows grid of zones in one JNI call — one YUV→BGR decode
    // for the full frame, then cols*rows crops/resizes.
    //
    // Returns a float array of length (cols*rows) × target² × 3, where zones
    // are stored in row-major order (row 0 left-to-right, then row 1, etc.).
    JNIEXPORT jfloatArray JNICALL
    Java_com_example_wasteclassifier_OpenCVHelper_preprocessGridZones(
        JNIEnv *env, jobject /* obj */,
        jbyteArray j_y_plane, jbyteArray j_u_plane, jbyteArray j_v_plane,
        jint y_row_stride, jint uv_row_stride, jint uv_pixel_stride,
        jint frame_width, jint frame_height,
        jint cols, jint rows,
        jint target_size)
    {
#ifndef HAVE_OPENCV
        LOGI("preprocessGridZones: OpenCV not compiled in — returning null");
        return nullptr;
#else
        YuvPlanes planes;
        if (!planes.acquire(env, j_y_plane, j_u_plane, j_v_plane))
        {
            LOGE("preprocessGridZones: GetByteArrayElements returned null");
            planes.release();
            return nullptr;
        }

        // Single full-frame YUV → BGR decode.
        cv::Mat full_bgr = yuv420_to_bgr(
            planes.y(), y_row_stride,
            planes.u(), planes.v(),
            uv_row_stride, uv_pixel_stride,
            frame_width, frame_height);
        planes.release();

        const int zone_w_base = frame_width / cols;
        const int zone_h_base = frame_height / rows;
        const int total_zones = cols * rows;
        const int zone_len = target_size * target_size * 3;
        const int total_len = total_zones * zone_len;

        jfloatArray j_result = env->NewFloatArray(total_len);
        if (!j_result)
        {
            LOGE("preprocessGridZones: NewFloatArray(%d) failed", total_len);
            return nullptr;
        }

        // Thread-local reusable buffer — grows to the maximum required size
        // and is then reused for every subsequent JNI call on the same thread.
        // No mutex needed: each Dispatchers.Default worker thread has its own instance.
        static thread_local std::vector<float> tl_output;
        if (static_cast<int>(tl_output.size()) < total_len)
        {
            tl_output.resize(total_len);
        }

        for (int row = 0; row < rows; ++row)
        {
            for (int col = 0; col < cols; ++col)
            {
                const int x = col * zone_w_base;
                const int y = row * zone_h_base;
                const int w = (col == cols - 1) ? frame_width - x : zone_w_base;
                const int h = (row == rows - 1) ? frame_height - y : zone_h_base;

                const int zone_idx = row * cols + col;
                zone_to_float32(full_bgr, x, y, w, h, target_size,
                                tl_output.data() + zone_idx * zone_len);
            }
        }

        env->SetFloatArrayRegion(j_result, 0, total_len, tl_output.data());
        LOGI("preprocessGridZones OK: frame=%dx%d grid=%dx%d target=%d",
             frame_width, frame_height, cols, rows, target_size);
        return j_result;
#endif
    }

    // ── preprocessHorizontalZones ─────────────────────────────────────────────
    //
    // Processes all 3 horizontal thirds in one JNI call.
    // Returns a float array of length 3 × target² × 3 (zones concatenated).
    JNIEXPORT jfloatArray JNICALL
    Java_com_example_wasteclassifier_OpenCVHelper_preprocessHorizontalZones(
        JNIEnv *env, jobject /* obj */,
        jbyteArray j_y_plane, jbyteArray j_u_plane, jbyteArray j_v_plane,
        jint y_row_stride, jint uv_row_stride, jint uv_pixel_stride,
        jint frame_width, jint frame_height,
        jint target_size)
    {
#ifndef HAVE_OPENCV
        LOGI("preprocessHorizontalZones: OpenCV not compiled in — returning null");
        return nullptr;
#else
        YuvPlanes planes;
        if (!planes.acquire(env, j_y_plane, j_u_plane, j_v_plane))
        {
            LOGE("preprocessHorizontalZones: GetByteArrayElements returned null");
            planes.release();
            return nullptr;
        }

        // Single full-frame YUV → BGR decode.
        cv::Mat full_bgr = yuv420_to_bgr(
            planes.y(), y_row_stride,
            planes.u(), planes.v(),
            uv_row_stride, uv_pixel_stride,
            frame_width, frame_height);
        planes.release();

        // Three horizontal zones: left / centre / right.
        const int zone_w = frame_width / 3;
        const int zone_w_r = frame_width - zone_w * 2; // right absorbs rounding

        const struct
        {
            int x;
            int w;
        } zones[3] = {
            {0, zone_w},
            {zone_w, zone_w},
            {zone_w * 2, zone_w_r},
        };

        const int zone_len = target_size * target_size * 3;
        const int total_len = 3 * zone_len;

        jfloatArray j_result = env->NewFloatArray(total_len);
        if (!j_result)
        {
            LOGE("preprocessHorizontalZones: NewFloatArray(%d) failed", total_len);
            return nullptr;
        }

        // Thread-local reusable buffer (see preprocessGridZones for rationale).
        static thread_local std::vector<float> tl_output;
        if (static_cast<int>(tl_output.size()) < total_len)
        {
            tl_output.resize(total_len);
        }

        for (int z = 0; z < 3; ++z)
        {
            zone_to_float32(full_bgr,
                            zones[z].x, 0, zones[z].w, frame_height,
                            target_size,
                            tl_output.data() + z * zone_len);
        }

        env->SetFloatArrayRegion(j_result, 0, total_len, tl_output.data());
        LOGI("preprocessHorizontalZones OK: frame=%dx%d target=%d",
             frame_width, frame_height, target_size);
        return j_result;
#endif
    }

} // extern "C"
