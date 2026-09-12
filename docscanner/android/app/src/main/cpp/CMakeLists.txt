cmake_minimum_required(VERSION 3.22)
project(opencv_wrapper)

set(CMAKE_CXX_STANDARD 17)

set(CMAKE_CXX_VISIBILITY_PRESET default)
set(CMAKE_VISIBILITY_INLINES_HIDDEN OFF)
set(ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON)

# Force flexible page sizes for Android NDK r28+
# define for source + pass to compiler:
add_definitions(-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON")
# Also set shared linker flag (helps propagate to linker)
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--no-warn-mismatch")


# OpenCV, Android
set(OpenCV_DIR "/home/rr/Android/OpenCV-android-sdk/sdk/native/jni")
find_package(OpenCV REQUIRED core imgproc imgcodecs)
include_directories(${OpenCV_INCLUDE_DIRS})

file(GLOB SRC_FILES *.cpp)
add_library(opencv_wrapper SHARED ${SRC_FILES})

# Favor throughput for the native image-processing library in the release APK.
target_compile_options(opencv_wrapper PRIVATE
  "$<$<CONFIG:Release>:-O3>"
)

# Link with OpenCV
target_link_libraries(opencv_wrapper
  ${OpenCV_LIBS}
  log
  android
)