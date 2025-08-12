#include <opencv2/opencv.hpp>
#include <vector>
#include <stdint.h>
#include <stdlib.h>

extern "C" {

void freeBuffer(void* inPtr) {
    if (inPtr) free(inPtr);
}

// Reads an inImage from disk into a cv::Mat
// Returns 1 if successful, 0 if failed
int readImageFromFile(const char* inFilePath, cv::Mat& outImage) {
    outImage = cv::imread(inFilePath, cv::IMREAD_UNCHANGED);
    return !outImage.empty();
}

// Writes a cv::Mat inImage to disk at given path
// Returns 1 if successful, 0 if failed
int writeImageToFile(const char* inFilePath, const cv::Mat& inImage) {
    return cv::imwrite(inFilePath, inImage);
}

// Warp inImage: read from path, process, write to output path
// Returns 1 if successful, 0 if failed
int warpImage(const char* inPhotoPath, const char* inWarpedPath) {
    cv::Mat image;
    if (!readImageFromFile(inPhotoPath, image)) {
        return 0; // Could not read input
    }
    
    // TODO: Apply your processing here
    // For now, just pass through
    
    if (!writeImageToFile(inWarpedPath, image)) {
        return 0; // Could not write output
    }
    
    return 1;
}

}