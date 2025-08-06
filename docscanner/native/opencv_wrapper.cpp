#include <opencv2/opencv.hpp>
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <vector>
#include <stdint.h>
#include <stdlib.h>

extern "C" {

// Convert incoming raw image buffer (e.g., RGBA) to cv::Mat
// Then process and return image buffer (as-is for now)

uint8_t* warpImage(uint8_t* inputBytes, int length, int* outLength) {
    std::vector<uint8_t> inputVec(inputBytes, inputBytes + length);

    // Decode image (assumes image is in PNG/JPG format)
    cv::Mat image = cv::imdecode(inputVec, cv::IMREAD_UNCHANGED);

    // Apply OpenCV logic here (for now: return as-is)

    std::vector<uint8_t> outputVec;
    cv::imencode(".png", image, outputVec);

    // Allocate buffer for Dart (don't free it here!)
    uint8_t* result = (uint8_t*)malloc(outputVec.size());
    memcpy(result, outputVec.data(), outputVec.size());

    *outLength = outputVec.size();
    return result;
}

}