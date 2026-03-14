package com.example.wasteclassifier

/**
 * JNI wrapper for the native yolo_preprocess library.
 *
 * Loads `libyolo_preprocess.so` (compiled from yolo_preprocess.cpp via CMake)
 * and exposes [preprocessZone] for fast YUV_420_888 → RGB → resize → Float32
 * preprocessing on a camera frame zone.
 *
 * Usage
 * -----
 * Check [isAvailable] before calling [preprocessZone].  If the native library
 * failed to load (e.g. missing OpenCV .so on the device), the Dart side falls
 * back to the pure-Dart ImageProcessor implementation.
 */
object OpenCVHelper {

    /**
     * True once the native library has been successfully loaded.
     * Stays false if [System.loadLibrary] throws [UnsatisfiedLinkError].
     */
    var isAvailable: Boolean = false
        private set

    init {
        isAvailable = try {
            System.loadLibrary("yolo_preprocess")
            // Library loaded; now verify OpenCV was compiled in.
            isOpenCVEnabled()
        } catch (e: UnsatisfiedLinkError) {
            false
        }
    }

    /**
     * Returns true only when the native library was compiled with OpenCV.
     * Called once during [init] to set [isAvailable] accurately.
     */
    private external fun isOpenCVEnabled(): Boolean

    /**
     * Preprocesses a rectangular zone of a YUV_420_888 camera frame.
     *
     * The function:
     *  1. Converts the full YUV frame to BGR using the plane strides.
     *  2. Crops the region defined by [zoneX], [zoneY], [zoneW], [zoneH].
     *  3. Converts BGR → RGB.
     *  4. Resizes to [targetSize] × [targetSize] with bilinear interpolation.
     *  5. Normalises pixel values to [0, 1].
     *
     * @return Float32 tensor of length [targetSize]×[targetSize]×3 (channel-last RGB),
     *         or `null` if the native call fails.
     */
    external fun preprocessZone(
        yPlane: ByteArray,
        uPlane: ByteArray,
        vPlane: ByteArray,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        frameWidth: Int,
        frameHeight: Int,
        zoneX: Int,
        zoneY: Int,
        zoneW: Int,
        zoneH: Int,
        targetSize: Int,
    ): FloatArray?

    /**
     * Preprocesses the left, centre, and right horizontal thirds of a camera
     * frame in a single JNI call.
     *
     * The planes are transferred across the JNI boundary only once, making
     * this ~3× cheaper than calling [preprocessZone] three times.
     *
     * @return FloatArray of length 3 × [targetSize] × [targetSize] × 3, where
     *   elements [0 … N-1]       = left zone tensor,
     *   elements [N … 2N-1]      = centre zone tensor,
     *   elements [2N … 3N-1]     = right zone tensor,
     *   and N = targetSize × targetSize × 3.
     */
    external fun preprocessHorizontalZones(
        yPlane: ByteArray,
        uPlane: ByteArray,
        vPlane: ByteArray,
        yRowStride: Int,
        uvRowStride: Int,
        uvPixelStride: Int,
        frameWidth: Int,
        frameHeight: Int,
        targetSize: Int,
    ): FloatArray?
}
