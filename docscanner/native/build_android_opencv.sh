#!/bin/bash
set -e

# Path to your NDK
export ANDROID_NDK_HOME="/home/rr/Android/Sdk/ndk/29.0.13113456"
if [ ! -d "$ANDROID_NDK_HOME" ]; then
  echo "ANDROID_NDK_HOME does not exist: $ANDROID_NDK_HOME"
  exit 1
fi

# Clean and build directory
#rm -rf build
mkdir -p build
cd build

# Run CMake to configure and generate Makefiles
  # CMAKE_BUILD_TYPE=Debug → ensures CMake honors debug symbols
  # -g → includes debug info (line numbers, variable names)
  # -O0 → disables optimizations so debugging is easier
  
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DOpenCV_DIR=/home/rr/Android/OpenCV-android-sdk/sdk/native/jni \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS="-g -O0 -std=c++17 -stdlib=libc++"

# Build
make -j$(nproc)

# Move .so library to correct directory
mkdir -p ../../android/app/src/main/jniLibs/arm64-v8a
cp -v libopencv_wrapper.so ../../android/app/src/main/jniLibs/arm64-v8a/
