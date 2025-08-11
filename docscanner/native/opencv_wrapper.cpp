#include <opencv2/opencv.hpp>
#include <vector>
#include <stdint.h>
#include <stdlib.h>

extern "C" {

void freeBuffer(void* ptr) {
    if (ptr) free(ptr);
}

void warpImage(
    const uint8_t* inBytes, int inLength,
    uint8_t** outBytes, int* outLength
) {
    // Image bytes to cv::Mat
    std::vector<uint8_t> inputVec(inBytes, inBytes + inLength);
    cv::Mat image = cv::imdecode(inputVec, cv::IMREAD_UNCHANGED);

    // Process image (currently just return as-is)
    std::vector<uint8_t> outputVec;
    cv::imencode(".png", image, outputVec);

    // Allocate output buffer for Dart
    *outLength = static_cast<int>(outputVec.size());
    *outBytes = (uint8_t*)malloc(*outLength);
    memcpy(*outBytes, outputVec.data(), *outLength);
}

}