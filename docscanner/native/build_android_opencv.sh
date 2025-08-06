#!/bin/bash

set -e

# Set this to your actual OpenCV Android SDK path
OPENCV_ANDROID_SDK="$HOME/Android/OpenCV-android-sdk"

# Output .so goes here
JNI_LIBS_PATH="../android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$JNI_LIBS_PATH"

rm -rf build
mkdir build && cd build

cmake \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-21 \
  -DOpenCV_DIR="$OPENCV_ANDROID_SDK/sdk/native/jni" \
  ..

make

cp libopencv_wrapper.so "$JNI_LIBS_PATH"
echo "✅ libopencv_wrapper.so copied to $JNI_LIBS_PATH"