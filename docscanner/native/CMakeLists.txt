cmake_minimum_required(VERSION 3.10)
project(opencv_wrapper)

set(CMAKE_CXX_STANDARD 17)

set(CMAKE_CXX_VISIBILITY_PRESET default)
set(CMAKE_VISIBILITY_INLINES_HIDDEN OFF)

# Set the OpenCV SDK path
set(OpenCV_DIR "/home/rr/Android/OpenCV-android-sdk/sdk/native/jni")

# Find OpenCV using its config
find_package(OpenCV REQUIRED core imgproc imgcodecs)

# Include directories manually to fix missing headers
include_directories(${OpenCV_INCLUDE_DIRS})

file(GLOB SRC_FILES *.cpp)
add_library(opencv_wrapper SHARED ${SRC_FILES})

# Link with OpenCV
target_link_libraries(opencv_wrapper ${OpenCV_LIBS})