#include <opencv2/opencv.hpp>
#include <string>
#include <stdint.h>
#include <stdlib.h>

extern "C" {

// ------------------ Instance Class ------------------
class ImageProcessor {
public:
    cv::Mat photo;
    cv::Mat warped;


    // Forward declarations of helper functions (implement later)
    static cv::Mat preFilter(const cv::Mat& input);
    static cv::Mat edgesFrom(const cv::Mat& input);
    static std::pair<cv::Mat, cv::Mat> documentMask(const cv::Mat& edges);
    static std::vector<std::vector<int>> detectCorners(const cv::Mat& mask);
    static double calculateTransformation(const cv::Mat& borderMask, std::vector<std::vector<int>>& corners);
    static void setHeightFromCorners(std::vector<std::vector<int>>& corners, double ratioValue);
    static void calculateBorderCutIn(const cv::Mat& borderMask, std::vector<std::vector<int>>& corners);
    static void applyBorderCutInToCorners(std::vector<std::vector<int>>& corners);
    static cv::Mat transformImage(const cv::Mat& input, const std::vector<std::vector<int>>& corners);
    
    
    bool loadPhoto(const std::string& inPath) {
        photo = cv::imread(inPath, cv::IMREAD_UNCHANGED);
        if (photo.empty()) return false;
        return true;
    }
    
    bool saveImage(const std::string& inPath, const cv::Mat& inImage) const {
        return cv::imwrite(inPath, inImage);
    }
    
    bool warpImage(
        const std::string& inWarpedPath,
        double* inOutRatioValue,
        std::vector<std::vector<int>>* inOutCorners
    ) {
        if (photo.empty()) return false;
        cv::Mat borderCorrectionMask;
        
        // Step 1: Detect or reuse corners
        if (inOutCorners == nullptr) {
            // 1a. Pre-filter to isolate shape
            cv::Mat prefiltered = preFilter(photo);
            
            // 1b. Detect edges
            cv::Mat edges = edgesFrom(prefiltered);
            
            // 1c. Get document mask & border correction mask
            cv::Mat mask;
            std::tie(mask, borderCorrectionMask) = documentMask(edges);
            
            // 1d. Detect corners
            *inOutCorners = detectCorners(mask);
        }
        
        // Step 2: Calculate or reuse ratio
        if (inOutRatioValue == nullptr) {
            *inOutRatioValue = calculateTransformation(borderCorrectionMask, *inOutCorners);
        } else {
            setHeightFromCorners(*inOutCorners, *inOutRatioValue);
            calculateBorderCutIn(borderCorrectionMask, *inOutCorners);
        }
        
        // Step 3: Apply border cut
        applyBorderCutInToCorners(*inOutCorners);
        
        // Step 4: Perspective transform
        warped = transformImage(photo, *inOutCorners);

        // Step 5: Save warped image
        if (!saveImage(inWarpedPath, warped)) {
            return false;
        }
        
        return true;
    }
};

// ------------------ Instance Lifecycle ------------------
ImageProcessor* createProcessor() {
    return new ImageProcessor();
}

void freeProcessor(ImageProcessor* inOutProcessor) {
    delete inOutProcessor;
}

// ------------------ Image Operations ------------------
int processorLoadPhoto(ImageProcessor* inOutProcessor, const char* inPhotoPath) {
    if (!inOutProcessor) return 0;
    return inOutProcessor->loadPhoto(inPhotoPath) ? 1 : 0;
}

int processorWarpImage(
    ImageProcessor* inOutProcessor,
    const char* inWarpedPath,
    double* inOutRatioValue, // Nullable double
    int* inOutCorners // Nullable flat array of ints
) {
    const int cornersCount = 4;
    if (!inOutProcessor) return 0;

    std::vector<std::vector<int>> cornersVec;
    std::vector<std::vector<int>>* cornersPtr = nullptr;

    // If Dart provided corners
    if (inOutCorners) {
        cornersVec.resize(cornersCount, std::vector<int>(2));
        for (int i = 0; i < cornersCount; i++) {
            cornersVec[i][0] = inOutCorners[i * 2];
            cornersVec[i][1] = inOutCorners[i * 2 + 1];
        }
        cornersPtr = &cornersVec;
    }

    bool result = inOutProcessor->warpImage(
        inWarpedPath,
        inOutRatioValue,
        cornersPtr
    );

    // If C++ calculated corners, return them
    if (result && cornersPtr && inOutCorners) {
        for (int i = 0; i < cornersCount; i++) {
            inOutCorners[i * 2]     = (*cornersPtr)[i][0];
            inOutCorners[i * 2 + 1] = (*cornersPtr)[i][1];
        }
    }

    return result ? 1 : 0;
}

}