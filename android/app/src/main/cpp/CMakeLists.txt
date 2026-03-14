cmake_minimum_required(VERSION 3.22.1)
project(yolo_preprocess VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ─── OpenCV Android SDK (optional) ────────────────────────────────────────
#
# Without OpenCV the library still compiles, but preprocessZone /
# preprocessHorizontalZones return nullptr.  The Dart side detects this
# via is_opencv_available → false and uses the pure-Dart fallback.
#
# To enable OpenCV:
#   1. Download the OpenCV Android SDK from https://opencv.org/releases/
#   2. Extract it; the directory structure should be:
#        android/opencv/sdk/native/jni/   ← contains OpenCVConfig.cmake
#   3. In android/local.properties add:
#        opencv.sdk.path=../opencv
#      (CMake receives the path via -DOPENCV_SDK_DIR in build.gradle.kts)

if (DEFINED OPENCV_SDK_DIR AND NOT OPENCV_SDK_DIR STREQUAL "")
    set(OpenCV_DIR "${OPENCV_SDK_DIR}/sdk/native/jni")
endif ()

find_package(OpenCV QUIET COMPONENTS core imgproc)

if (OpenCV_FOUND)
    message(STATUS "OpenCV ${OpenCV_VERSION} found — native preprocessing enabled")
    add_compile_definitions(HAVE_OPENCV)
else ()
    message(WARNING
        "OpenCV not found — native preprocessing will be disabled.\n"
        "Set opencv.sdk.path in android/local.properties to enable it.")
endif ()

# ─── Shared library ───────────────────────────────────────────────────────

add_library(yolo_preprocess SHARED
    yolo_preprocess.cpp)

if (OpenCV_FOUND)
    target_include_directories(yolo_preprocess PRIVATE ${OpenCV_INCLUDE_DIRS})
    target_link_libraries(yolo_preprocess ${OpenCV_LIBS} android log)
else ()
    target_link_libraries(yolo_preprocess android log)
endif ()
