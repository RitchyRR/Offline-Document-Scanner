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
    
    bool loadPhoto(const std::string& path) {
        photo = cv::imread(path, cv::IMREAD_UNCHANGED);
        if (photo.empty()) return false;
        return true;
    }
    
    bool saveImage(const std::string& path, const cv::Mat& image) const {
        return cv::imwrite(path, image);
    }
    
    bool warpImage(const std::string& warpedPath) {
        if (photo.empty()) return false;
        warped = photo.clone();
        
        // TODO: Apply your processing to `warped` here
        // Currently: pass-through (already copied from photo)
        
        return saveImage(warpedPath, warped);
    }
};

// ------------------ Instance Lifecycle ------------------
ImageProcessor* createProcessor() {
    return new ImageProcessor();
}

void freeProcessor(ImageProcessor* processor) {
    delete processor;
}

// ------------------ Image Operations ------------------
int processorLoadPhoto(ImageProcessor* processor, const char* photoPath) {
    if (!processor) return 0;
    return processor->loadPhoto(photoPath) ? 1 : 0;
}

int processorWarpImage(ImageProcessor* processor, const char* warpedPath) {
    if (!processor) return 0;
    return processor->warpImage(warpedPath) ? 1 : 0;
}

}