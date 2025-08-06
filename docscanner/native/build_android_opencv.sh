#!/bin/bash
set -e

# Make sure this points to your actual NDK location
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-"$HOME/Android/Sdk/ndk/29.0.13113456"}

# Check if the NDK exists
if [ ! -d "$ANDROID_NDK_HOME" ]; then
  echo "ANDROID_NDK_HOME does not exist: $ANDROID_NDK_HOME"
  exit 1
fi

# Clean and build directory
mkdir -p build
cd build

# Run CMake to configure and generate Makefiles
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21 \
  -DOpenCV_DIR=/home/rr/Android/OpenCV-android-sdk/sdk/native/jni

# Build it
make -j$(nproc)

# Move .so library to correct directory
mkdir -p ../../../android/app/src/main/jniLibs/arm64-v8a
cp libopencv_wrapper.so ../../../android/app/src/main/jniLibs/arm64-v8a/

echo "Build files have been copied to:  ../../../android/app/src/main/jniLibs/arm64-v8a/"