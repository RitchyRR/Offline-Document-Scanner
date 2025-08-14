#include <opencv2/opencv.hpp>
#include <string>
#include <stdint.h>
#include <stdlib.h>

#include "native_log.h"



extern "C" {

// ------------------ Instance Class ------------------
class ImageProcessor {
private:
    cv::Mat photo;
    cv::Mat warped;
    std::vector<double> availableAspectRatios;


    // Pre filter before edge detection
    cv::Mat _preFilter(const cv::Mat& imIn, int K) {
        LOG_ENTRY();
        cv::Mat preFiltered = imIn.clone();
        
        // Histogram stretching
        preFiltered = _stretchMat(preFiltered, 0.001, 0.999, std::numeric_limits<double>::quiet_NaN());
        
        // Gaussian blur (kernel size 3x3, sigma = 0)
        cv::GaussianBlur(preFiltered, preFiltered, cv::Size(3, 3), 0);
        
        // Median blur (kernel size 3)
        cv::medianBlur(preFiltered, preFiltered, 3);
        
        // Remove sharpening glow
        int kGlow = std::clamp(K / 17, 3, std::numeric_limits<int>::max());
        if (kGlow % 2 == 0) kGlow += 1;
        cv::Mat kernelGlow = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(kGlow, kGlow));
        cv::morphologyEx(preFiltered, preFiltered, cv::MORPH_OPEN, kernelGlow, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        
        // Remove text
        preFiltered = _closingCircleApprox(preFiltered, K);
        
        LOG_EXIT();
        return preFiltered;
    }

    // Gamma correction helper
    cv::Mat _applyGammaCorrection(const cv::Mat& src, double gamma) {
        LOG_ENTRY();
        CV_Assert(gamma > 0);
        cv::Mat lut(1, 256, CV_8UC1);
        for (int i = 0; i < 256; i++) {
            lut.at<uchar>(i) = cv::saturate_cast<uchar>(std::pow(i / 255.0, gamma) * 255.0);
        }
        cv::Mat dst;
        cv::LUT(src, lut, dst);
        LOG_EXIT();
        return dst;
    }

    // Histogram stretching with percentiles
    cv::Mat _stretchMat(const cv::Mat& matIn, double lowPercentile = 0.005,
                    double highPercentile = 0.995, double gamma = std::numeric_limits<double>::quiet_NaN()) {
        LOG_ENTRY();
        cv::Mat ref;
        int height = matIn.rows;
        int width = matIn.cols;
        
        // Resize if large
        if (height > 1000 || width > 1000) {
            cv::resize(matIn, ref, cv::Size(width / 4, height / 4));
        } else {
            ref = matIn.clone();
        }
        
        // Convert to grayscale if 3 channels
        if (ref.channels() == 3) {
            cv::cvtColor(ref, ref, cv::COLOR_BGR2GRAY);
        }
        
        // Flatten pixel values
        std::vector<uchar> refList;
        if (ref.isContinuous()) {
            refList.assign(ref.datastart, ref.dataend);
        } else {
            for (int r = 0; r < ref.rows; r++) {
                refList.insert(refList.end(), ref.ptr<uchar>(r), ref.ptr<uchar>(r) + ref.cols);
            }
        }
        
        std::sort(refList.begin(), refList.end());

        int lowIndex = static_cast<int>(refList.size() * lowPercentile);
        double lowValue = static_cast<double>(refList[lowIndex]);
        int highIndex = static_cast<int>(refList.size() * highPercentile);
        double highValue = static_cast<double>(refList[highIndex]);

        // Normalize (matching Dart's alpha/beta style)
        cv::Mat matOut;
        matIn.convertTo(matOut, CV_32F); // work in float
        matOut = (matOut - lowValue) * (255.0 / (highValue - lowValue));
        cv::threshold(matOut, matOut, 255, 255, cv::THRESH_TRUNC);
        cv::threshold(matOut, matOut, 0, 0, cv::THRESH_TOZERO);
        matOut.convertTo(matOut, matIn.type());
        
        // Optional gamma correction
        if (!isnan(gamma)) {
            matOut = _applyGammaCorrection(matOut, gamma);
        }
        
        LOG_EXIT();
        return matOut;
    }

    // Closing circle approximation
    cv::Mat _closingCircleApprox(const cv::Mat& imIn, int filterDiameter) {
        LOG_ENTRY();
        // Kernel sizes
        int kCross = std::max(3, filterDiameter);
        if (kCross % 2 == 0) kCross += 1;
        
        int kRect = static_cast<int>(std::round(kCross / std::sqrt(2.0)));
        if (kRect % 2 == 0) kRect += 1;
        
        int kFatCrossRect = static_cast<int>(std::round(0.475 * filterDiameter));
        if (kFatCrossRect % 2 == 0) kFatCrossRect += 1;
        
        int kFatCrossCross = static_cast<int>(std::round(0.4 * filterDiameter));
        if (kFatCrossCross % 2 == 0) kFatCrossCross += 1;
        
        // Kernels
        cv::Mat kernelCross = cv::getStructuringElement(cv::MORPH_CROSS, cv::Size(kCross, kCross));
        cv::Mat kernelRect = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(kRect, kRect));
        cv::Mat kernelFatCrossRect = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(kFatCrossRect, kFatCrossRect));
        cv::Mat kernelFatCrossCross = cv::getStructuringElement(cv::MORPH_CROSS, cv::Size(kFatCrossCross, kFatCrossCross));
        
        // --- 1. Dilate ---
        cv::Mat imCross, imRect, imFatCross;
        
        cv::morphologyEx(imIn, imCross, cv::MORPH_DILATE, kernelCross, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(imIn, imRect, cv::MORPH_DILATE, kernelRect, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        
        cv::morphologyEx(imIn, imFatCross, cv::MORPH_DILATE, kernelFatCrossRect, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(imFatCross, imFatCross, cv::MORPH_DILATE, kernelFatCrossCross, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        
        // --- 2. Max ---
        cv::Mat imCircle;
        cv::max(imCross, imRect, imCircle);
        cv::max(imCircle, imFatCross, imCircle);
        
        // --- 3. Erode ---
        cv::morphologyEx(imCircle, imCross, cv::MORPH_ERODE, kernelCross, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(imCircle, imRect, cv::MORPH_ERODE, kernelRect, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        
        cv::morphologyEx(imCircle, imFatCross, cv::MORPH_ERODE, kernelFatCrossCross, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(imFatCross, imFatCross, cv::MORPH_ERODE, kernelFatCrossRect, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        
        // --- 4. Min ---
        cv::min(imCross, imRect, imCircle);
        cv::min(imCircle, imFatCross, imCircle);
        
        LOG_EXIT();
        return imCircle;
    }
    
    // Detect edges
    cv::Mat _edgeDetection(const cv::Mat& prefiltered, double K) {
        LOG_ENTRY();
        
        double baseThreshold = 55.0;
        double highT = baseThreshold + K * 0.1;
        double lowT = 0.7 * highT;
        
        // Step 1: grayscale edges
        cv::Mat gray;
        cv::cvtColor(prefiltered, gray, cv::COLOR_BGR2GRAY);
        cv::Mat edges;
        cv::Canny(gray, edges, lowT, highT);
        
        // Add saturation-based edges
        cv::Mat hsv;
        cv::cvtColor(prefiltered, hsv, cv::COLOR_BGR2HSV);
        std::vector<cv::Mat> hsvChannels;
        cv::split(hsv, hsvChannels);
        cv::Mat sEdges;
        cv::Canny(hsvChannels[1], sEdges, lowT, highT);
        cv::add(edges, sEdges, edges);
        
        // Step 2: Edge density
        int edgePixelsCount = cv::countNonZero(edges);
        int totalPixels = prefiltered.rows * prefiltered.cols;
        double edgeDensity = static_cast<double>(edgePixelsCount) / static_cast<double>(totalPixels);
        
        // Step 3: Adjust thresholds to target density
        double targetDensity = 0.004;
        double scale = ((edgeDensity / targetDensity + 0.25) / 1.25);
        scale = std::max(0.5, std::min(2.0, scale));

        highT *= scale;
        lowT = 0.7 * highT;
        
        // Step 4: Run Canny again with adjusted thresholds
        cv::Canny(gray, edges, lowT, highT);
        cv::Canny(hsvChannels[1], sEdges, lowT, highT);
        cv::add(edges, sEdges, edges);
        
        LOG_EXIT();
        return edges;
    }
    
    // Test if white pixels spilled over to the outer edges of the image
    bool _testNoSpillover(const cv::Mat& testShape) {
        LOG_ENTRY();
        
        CV_Assert(testShape.type() == CV_8UC1 || testShape.type() == CV_8U);
        int rows = testShape.rows;
        int cols = testShape.cols;
        
        auto pixelAt = [&](int r, int c) {
            LOG_EXIT();
        return testShape.at<uchar>(r, c);
        };
        
        if (pixelAt(0, 0) == 0 &&
            pixelAt(0, cols / 2) == 0 &&
            pixelAt(0, cols - 1) == 0 &&
            pixelAt(rows - 1, 0) == 0 &&
            pixelAt(rows - 1, cols / 2) == 0 &&
            pixelAt(rows - 1, cols - 1) == 0 &&
            pixelAt(rows / 2, 0) == 0 &&
            pixelAt(rows / 2, cols - 1) == 0) {
            LOG_EXIT();
        return true;
        }
        LOG_EXIT();
        return false;
    }
    
    // Standard Hough with infinitely long edges
    cv::Mat _houghEdges1(const cv::Mat& edges, int K, int maxLinesCount) {
        LOG_ENTRY();
        
        CV_Assert(edges.type() == CV_8UC1);
        
        const double rhoRes   = std::max(1.0, K * 0.125);   // pixel resolution
        const double thetaRes = CV_PI / 180.0;              // 1 degree
        const int threshold   = std::max(1, static_cast<int>(K * 20.0));
        
        std::vector<cv::Vec2f> lines;
        cv::HoughLines(edges, lines, rhoRes, thetaRes, threshold);
        
        const int rows = edges.rows;
        const int cols = edges.cols;
        
        cv::Mat houghEdges = cv::Mat::zeros(rows, cols, CV_8UC1);
        
        const int drawCount = std::min(static_cast<int>(lines.size()), maxLinesCount);
        for (int i = 0; i < drawCount; ++i) {
            const float rho   = lines[i][0];
            const float theta = lines[i][1];
            
            const double a = std::cos(theta);
            const double b = std::sin(theta);
            const double x0 = a * rho;
            const double y0 = b * rho;
            
            // Extend a long line
            const int x1 = static_cast<int>(std::round(x0 + K * 100.0 * (-b)));
            const int y1 = static_cast<int>(std::round(y0 + K * 100.0 * ( a)));
            const int x2 = static_cast<int>(std::round(x0 - K * 100.0 * (-b)));
            const int y2 = static_cast<int>(std::round(y0 - K * 100.0 * ( a)));

            cv::line(houghEdges, cv::Point(x1, y1), cv::Point(x2, y2), cv::Scalar(255), K, cv::LINE_AA);
        }
        LOG_EXIT();
        return houghEdges;
    }

    // Probabilistic Hough, with limited edges lengths, extended by the parameter
    cv::Mat _houghEdges2(const cv::Mat& edges, int K, double extendedBy) {
        LOG_ENTRY();
        
        CV_Assert(edges.type() == CV_8UC1);

        const double rhoRes      = std::max(1.0, K * 0.125);
        const double thetaRes    = CV_PI / 180.0;
        const int threshold      = std::max(1, static_cast<int>(K * 21.5));
        const double minLineLen  = std::max(4.0, K * 10.0);
        const double maxLineGap  = K * 7.5;
        
        std::vector<cv::Vec4i> segments;
        cv::HoughLinesP(edges, segments, rhoRes, thetaRes, threshold, minLineLen, maxLineGap);
        
        cv::Mat houghEdges = cv::Mat::zeros(edges.rows, edges.cols, CV_8UC1);

        for (const auto& seg : segments) {
            int x1 = seg[0], y1 = seg[1], x2 = seg[2], y2 = seg[3];
            const int dx = x2 - x1;
            const int dy = y2 - y1;

            const int ex1 = static_cast<int>(std::round(x1 - dx * extendedBy));
            const int ey1 = static_cast<int>(std::round(y1 - dy * extendedBy));
            const int ex2 = static_cast<int>(std::round(x2 + dx * extendedBy));
            const int ey2 = static_cast<int>(std::round(y2 + dy * extendedBy));

            cv::line(houghEdges, cv::Point(ex1, ey1), cv::Point(ex2, ey2), cv::Scalar(255), 1, cv::LINE_AA);
        }
        LOG_EXIT();
        return houghEdges;
    }

    // Mask from hough edges
    cv::Mat _houghShape1(const cv::Mat& edges, int K) {
        LOG_ENTRY();
        
        CV_Assert(edges.type() == CV_8UC1);
        
        cv::Mat shape1 = edges.clone();
        const cv::Point seed(edges.cols / 2, edges.rows / 2);

        // flood fill interior
        cv::floodFill(shape1, seed, cv::Scalar(255));

        // remove edge pixels (keep filled interior only)
        cv::subtract(shape1, edges, shape1);
        
        int kSize = 2 * K;
        if (kSize % 2 == 0) ++kSize;
        cv::Mat kernel = cv::Mat::ones(kSize, kSize, CV_8UC1);

        cv::dilate(shape1, shape1, kernel, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        LOG_EXIT();
        return shape1;
    }
    
    // Mask from probabilistic hough edges
    cv::Mat _houghShape2(const cv::Mat& edges) {
        LOG_ENTRY();
        
        CV_Assert(edges.type() == CV_8UC1);

        cv::Mat kernel1 = cv::Mat::ones(3, 3, CV_8UC1);
        cv::Mat dilEdges;
        cv::dilate(edges, dilEdges, kernel1, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        
        cv::Mat shape1 = dilEdges.clone();
        const cv::Point seed(edges.cols / 2, edges.rows / 2);
        cv::floodFill(shape1, seed, cv::Scalar(255));

        cv::subtract(shape1, dilEdges, shape1);

        cv::Mat kernel2 = cv::Mat::ones(5, 5, CV_8UC1);
        cv::dilate(shape1, shape1, kernel2, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        LOG_EXIT();
        return shape1;
    }

    // Mask from edges
    cv::Mat _tightRiskyShape(const cv::Mat& edges) {
        LOG_ENTRY();
        
        CV_Assert(edges.type() == CV_8UC1);
        
        cv::Mat kernel1 = cv::Mat::ones(3, 3, CV_8UC1);
        cv::Mat dilEdges;
        cv::dilate(edges, dilEdges, kernel1, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);

        cv::Mat shape1 = dilEdges.clone();
        const cv::Point seed(edges.cols / 2, edges.rows / 2);
        cv::floodFill(shape1, seed, cv::Scalar(255));

        cv::subtract(shape1, dilEdges, shape1);

        cv::Mat kernel2 = cv::Mat::ones(5, 5, CV_8UC1);
        cv::dilate(shape1, shape1, kernel2, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        LOG_EXIT();
        return shape1;
    }

    // Mask from closed edges
    cv::Mat _mediumShape(const cv::Mat& edges, int K) {
        LOG_ENTRY();
        
        CV_Assert(edges.type() == CV_8UC1);

        int kSizeD = (K / 2) * 2 + 1;
        int kSizeE = (K / 3) * 2 + 1;

        cv::Mat kernelDilate = cv::Mat::ones(kSizeD, kSizeD, CV_8UC1);
        cv::Mat kernelErode  = cv::Mat::ones(kSizeE, kSizeE, CV_8UC1);

        cv::Mat dilEdges;
        cv::dilate(edges, dilEdges, kernelDilate, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        
        cv::Mat edgesClosed;
        cv::erode(dilEdges, edgesClosed, kernelErode, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        
        cv::Mat shape1 = edgesClosed.clone();
        const cv::Point seed(edges.cols / 2, edges.rows / 2);
        cv::floodFill(shape1, seed, cv::Scalar(255));

        cv::subtract(shape1, edgesClosed, shape1);

        int k2 = (kSizeD - kSizeE + 2);
        if (k2 < 1) k2 = 1;
        if (k2 % 2 == 0) ++k2;
        cv::Mat kernel2 = cv::Mat::ones(k2, k2, CV_8UC1);
        
        cv::dilate(shape1, shape1, kernel2, cv::Point(-1, -1), 1, cv::BORDER_CONSTANT);
        LOG_EXIT();
        return shape1;
    }
    
    // Best document mask + Mask for border correction
    void _documentMask(
        const cv::Mat& edges, 
        int K,
        bool* usingHough,
        cv::Mat* outMask,
        cv::Mat* outBorderCorrectionMask
    ) {
        LOG_ENTRY();
        LOG_VAR(edges);
        LOG_VAR(K);
        LOG_VAR(usingHough);
        
        CV_Assert(edges.type() == CV_8UC1);
        
        int edgesMaskSize = 0;
        int houghMaskSize = 0;
        
        // 3. Mask <- filling Edges
        cv::Mat edgesMask = _tightRiskyShape(edges);
        
        // 4. Mask <- filling Hough Edges
        cv::Mat houghEdges1Mat = _houghEdges1(edges, K, 18); // maxLinesCount = 18
        cv::Mat houghEdges2Mat = _houghEdges2(edges, K, 0.25);
        cv::Mat houghEdges;

        cv::Mat houghShape1Mat = _houghShape1(houghEdges1Mat, K);
        bool hough1NoSpillover = false;
        if (_testNoSpillover(houghShape1Mat)) {
            hough1NoSpillover = true;
        }
        
        if (hough1NoSpillover) {
            cv::multiply(houghEdges1Mat, houghEdges2Mat, houghEdges);
        } else {
            houghEdges = houghEdges2Mat.clone();
        }
        
        cv::Mat houghMask = _houghShape2(houghEdges);

        // Check edgesMask
        if (_testNoSpillover(edgesMask)) {
            edgesMaskSize = cv::countNonZero(edgesMask);
        } else {
            edgesMask = _mediumShape(edges, K);
            if (_testNoSpillover(edgesMask)) {
                edgesMaskSize = cv::countNonZero(edgesMask);
            }
        }

        // Check houghMask
        if (_testNoSpillover(houghMask)) {
            houghMaskSize = cv::countNonZero(houghMask);
        } else {
            houghEdges2Mat = _houghEdges2(edges, K, 0.5);
            if (hough1NoSpillover) {
                cv::multiply(houghEdges1Mat, houghEdges2Mat, houghEdges);
            } else {
                houghEdges = houghEdges2Mat.clone();
            }
            houghMask = _houghShape2(houghEdges);
            if (_testNoSpillover(houghMask)) {
                houghMaskSize = cv::countNonZero(houghMask);
            } else {
                houghEdges2Mat = _houghEdges2(edges, K, 0.75);
                if (hough1NoSpillover) {
                    cv::multiply(houghEdges1Mat, houghEdges2Mat, houghEdges);
                } else {
                    houghEdges = houghEdges2Mat.clone();
                }
                houghMask = _houghShape2(houghEdges);
                if (_testNoSpillover(houghMask)) {
                    houghMaskSize = cv::countNonZero(houghMask);
                }
            }
        }
        
        cv::Mat mask;
        cv::Mat borderCorrectionMask;
        
        // Use larger mask (for corner detection)
        if (edgesMaskSize != 0 && edgesMaskSize > houghMaskSize) {
            mask = edgesMask.clone();
        } else if (houghMaskSize != 0) {
            mask = houghMask.clone();
            *usingHough = true;
        }

        // Fallback: Combine edges and Hough edges
        if (mask.empty()) {
            cv::Mat combinedEdges;
            cv::add(edges, houghEdges, combinedEdges); // logical OR alternative
            edgesMask = _tightRiskyShape(combinedEdges);
            if (_testNoSpillover(edgesMask)) {
                mask = edgesMask.clone();
            } else {
                edgesMask = _mediumShape(combinedEdges, K);
                if (_testNoSpillover(edgesMask)) {
                    mask = edgesMask.clone();
                }
            }
        }
        
        // Use edgesMask for border correction if available
        if (edgesMaskSize != 0) {
            borderCorrectionMask = edgesMask.clone();
        }
        
        // Empty fallback
        if (mask.empty()) {
            mask = cv::Mat::zeros(edges.rows, edges.cols, CV_8UC1);
        }
        if (borderCorrectionMask.empty()) {
            borderCorrectionMask = mask.clone();
        }
        
        LOG_VAR(mask);
        LOG_VAR(borderCorrectionMask);
        *outMask = mask;
        *outBorderCorrectionMask = borderCorrectionMask;
        LOG_EXIT();
    }
    
    std::vector<cv::Point> _toPoints(
        const cv::Mat& detectedCorners, 
        int xOffset = 0, int yOffset = 0
    ) {
        LOG_ENTRY();
        LOG_VAR(detectedCorners);
        LOG_VAR(xOffset);
        LOG_VAR(yOffset);
        
        std::vector<cv::Point> edgePoints;
        cv::Mat nonZero;
        cv::findNonZero(detectedCorners, nonZero);
        
        for (int i = 0; i < nonZero.total(); ++i) {
            cv::Point p = nonZero.at<cv::Point>(i);
            edgePoints.emplace_back(p.x + xOffset, p.y + yOffset);
        }
        
        LOG_VAR(edgePoints);
        LOG_EXIT();
        return edgePoints;
    }
    
    std::vector<std::vector<int>> _detectCorners(const cv::Mat& shape, int K) {
        LOG_ENTRY();
        
        int hitmissSize = static_cast<int>(std::round(K * 1.5)) * 2 + 1;
        int hitmissTolerance = std::max(1, K / 10);
        int rows = shape.rows;
        int cols = shape.cols;
        
        cv::Mat kernel1 = cv::Mat::zeros(hitmissSize, hitmissSize, CV_8SC1);
        kernel1.at<char>(hitmissSize / 2, hitmissSize / 2) = 1;
        kernel1.at<char>(hitmissSize / 2 - 1, hitmissSize / 2 - 1) = -1;
        kernel1.at<char>(hitmissSize - hitmissTolerance, 0) = -1;
        kernel1.at<char>(0, hitmissSize - hitmissTolerance) = -1;
        
        cv::Mat kernel2, kernel3, kernel4;
        cv::rotate(kernel1, kernel2, cv::ROTATE_90_COUNTERCLOCKWISE);
        cv::rotate(kernel1, kernel3, cv::ROTATE_90_CLOCKWISE);
        cv::rotate(kernel1, kernel4, cv::ROTATE_180);
        
        cv::Mat detectedCorners1 = shape(cv::Range(0, rows / 2), cv::Range(0, cols / 2));
        cv::Mat detectedCorners2 = shape(cv::Range(rows / 2, rows), cv::Range(0, cols / 2));
        cv::Mat detectedCorners3 = shape(cv::Range(0, rows / 2), cv::Range(cols / 2, cols));
        cv::Mat detectedCorners4 = shape(cv::Range(rows / 2, rows), cv::Range(cols / 2, cols));
        
        cv::morphologyEx(detectedCorners1, detectedCorners1, cv::MORPH_HITMISS, kernel1, cv::Point(-1,-1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(detectedCorners2, detectedCorners2, cv::MORPH_HITMISS, kernel2, cv::Point(-1,-1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(detectedCorners3, detectedCorners3, cv::MORPH_HITMISS, kernel3, cv::Point(-1,-1), 1, cv::BORDER_REPLICATE);
        cv::morphologyEx(detectedCorners4, detectedCorners4, cv::MORPH_HITMISS, kernel4, cv::Point(-1,-1), 1, cv::BORDER_REPLICATE);

        std::vector<cv::Point> outerPoints(4, cv::Point(0, 0));
        std::vector<int> fallbacks;

        auto xy1 = _toPoints(detectedCorners1, 0, 0);
        auto xy2 = _toPoints(detectedCorners2, 0, rows / 2);
        auto xy3 = _toPoints(detectedCorners3, cols / 2, 0);
        auto xy4 = _toPoints(detectedCorners4, cols / 2, rows / 2);

        try {
            outerPoints[0] = *std::max_element(xy1.begin(), xy1.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (-a.y - a.x) < (-b.y - b.x); });
        } catch(...) { fallbacks.push_back(0); outerPoints[0] = cv::Point(cols / 2 - 1, rows / 2 - 1); }

        try {
            outerPoints[1] = *std::max_element(xy2.begin(), xy2.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (a.y - a.x) < (b.y - b.x); });
        } catch(...) { fallbacks.push_back(1); outerPoints[1] = cv::Point(cols / 2 - 1, rows / 2 + 1); }

        try {
            outerPoints[2] = *std::max_element(xy3.begin(), xy3.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (-a.y + a.x) < (-b.y + b.x); });
        } catch(...) { fallbacks.push_back(2); outerPoints[2] = cv::Point(cols / 2 + 1, rows / 2 - 1); }
        
        try {
            outerPoints[3] = *std::max_element(xy4.begin(), xy4.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (a.y + a.x) < (b.y + b.x); });
        } catch(...) { fallbacks.push_back(3); outerPoints[3] = cv::Point(cols / 2 + 1, rows / 2 + 1); }

        if (fallbacks.size() == 4) {
            outerPoints = { {0,0}, {0,rows-1}, {cols-1,0}, {cols-1, rows-1} };
        } else if (!fallbacks.empty()) {
            for (int cornerIndex : fallbacks) {
                int xRef=-1, yRef=-1;
                switch(cornerIndex) {
                    case 0: xRef=1; yRef=2; break;
                    case 1: xRef=0; yRef=3; break;
                    case 2: xRef=3; yRef=0; break;
                    case 3: xRef=2; yRef=1; break;
                }
                outerPoints[cornerIndex] = cv::Point(outerPoints[xRef].x, outerPoints[yRef].y);
            }
        }
        
        std::vector<std::vector<int>> outerPointsList;
        for (auto& pt : outerPoints) {
            outerPointsList.push_back({pt.y, pt.x});
        }
        
        LOG_VAR(outerPointsList);
        for (size_t i = 0; i < outerPointsList.size(); ++i) {
            LOGD("outerPointsList[%zu] = (%d, %d)", i, outerPointsList[i][0], outerPointsList[i][1]);
        }
        LOG_EXIT();
        return outerPointsList;
    }
    
    double _percentileValueInt(const std::vector<int>& values, double percentile) {
        LOG_ENTRY();
        
        int length = values.size();
        if (length == 0) {
            LOG_EXIT();
            return 0.0;
        }
        std::vector<int> sorted = values;
        std::sort(sorted.begin(), sorted.end());
        int idx = std::clamp(static_cast<int>(percentile * length), 0, length - 1);
        
        LOG_EXIT();
        return sorted[idx];
    }

    double _calculateAspectRatio(const std::vector<std::vector<int>>& corners) {
        LOG_ENTRY();
        
        double widthTop = std::hypot(corners[2][0] - corners[0][0], corners[2][1] - corners[0][1]);
        double widthBottom = std::hypot(corners[3][0] - corners[1][0], corners[3][1] - corners[1][1]);
        double heightLeft = std::hypot(corners[1][0] - corners[0][0], corners[1][1] - corners[0][1]);
        double heightRight = std::hypot(corners[3][0] - corners[2][0], corners[3][1] - corners[2][1]);
        
        double avgWidth = (widthTop + widthBottom) / 2.0;
        double avgHeight = (heightLeft + heightRight) / 2.0;
        
        double widthDistortion = widthTop / widthBottom;
        double heightDistortion = heightLeft / heightRight;
        
        if (widthDistortion < 1.0) widthDistortion = 1.0 / widthDistortion;
        if (heightDistortion < 1.0) heightDistortion = 1.0 / heightDistortion;
        
        double correctedHeight = avgHeight * std::sqrt(widthDistortion);
        double correctedWidth = avgWidth * std::sqrt(heightDistortion);
        
        LOG_EXIT();
        return correctedHeight / correctedWidth;
    }
    
    double _matchAspectRatioAndOrientation(double calculatedRatioIn) {
        LOG_ENTRY();
        
        double matchingValue = std::sqrt(2.0);
        bool portrait = true;
        double portraitValue = calculatedRatioIn;
        
        if (calculatedRatioIn < 1.0) {
            portraitValue = 1.0 / calculatedRatioIn;
            portrait = false;
        }
        
        double smallestDifference = std::numeric_limits<double>::infinity();
        for (const double ar : availableAspectRatios) {
            double diff = std::abs(ar - portraitValue);
            if (diff < smallestDifference) {
                smallestDifference = diff;
                matchingValue = ar;
            }
        }
        
        LOG_EXIT();
        return portrait ? matchingValue : 1.0 / matchingValue;
    }

    void _setHeightFromCorners(
        const std::vector<std::vector<int>>& inCorners, 
        double inRatio,
        int* K, int* height, int* width
    ) {
        LOG_ENTRY();
        
        *height = std::max(abs(inCorners[1][0] - inCorners[0][0]), abs(inCorners[3][0] - inCorners[2][0]));
        *width = std::max(abs(inCorners[2][1] - inCorners[0][1]), abs(inCorners[3][1] - inCorners[1][1]));
        
        if (*width < std::round(*height / inRatio)) {
            *width = std::round(*height / inRatio);
        } else {
            *height = std::round(*width * inRatio);
        }
        
        *height = std::clamp(*height, 10, std::numeric_limits<int>::max());
        *width = std::clamp(*width, 10, std::numeric_limits<int>::max());
        *K = std::clamp((*height + *width) / 50, 3, std::numeric_limits<int>::max());
        LOG_EXIT();
    }
    
    void _calculateBorderCutInPerSide(
        int borderIndex, std::vector<int> depths, 
        std::vector<int>* borderCutIn
    ) {
        LOG_ENTRY();
        
        int start = depths.size() / 40;
        int end = depths.size() * 39 / 40;
        depths = std::vector<int>(depths.begin() + start, depths.begin() + end);
        
        if (!(*borderCutIn).empty()) {
            (*borderCutIn)[borderIndex * 2] = _percentileValueInt(
                std::vector<int>(depths.begin(), depths.begin() + depths.size() / 2), 0.75
            );
            (*borderCutIn)[borderIndex * 2 + 1] = _percentileValueInt(
                std::vector<int>(depths.begin() + depths.size() / 2, depths.end()), 0.75
            );
        }
        LOG_EXIT();
    }
    
    void _calculateBorderCutIn(
        cv::Mat* borderCorrectionMask, 
        std::vector<std::vector<int>>& corners, 
        bool usingHough,
        std::vector<int>* borderCutIn,
        int K, int height, int width
    ) {
        LOG_ENTRY();
        
        if (!borderCorrectionMask && !(*borderCutIn).empty()) (*borderCutIn).clear();
        if ((*borderCutIn).empty()) return;
        
        cv::Mat warpedBCMask = _transformImage(*borderCorrectionMask, corners, height, width);

        int maxCutIn = usingHough ? std::clamp(static_cast<int>(K * 0.2), 1, std::numeric_limits<int>::max())
                                : std::clamp(static_cast<int>(K * 0.4), 1, std::numeric_limits<int>::max());
        
        // Top
        std::vector<int> depths(width, 0);
        for (int j = 0; j < width; j++) {
            for (int i = 0; i < maxCutIn; i++) {
                if (warpedBCMask.at<int>(i, j) == 0) depths[j] = i;
                else break;
            }
        }
        _calculateBorderCutInPerSide(0, depths, borderCutIn);
        
        // Bottom
        depths.assign(width, 0);
        for (int j = 0; j < width; j++) {
            for (int i = height - 1; i > height - maxCutIn; i--) {
                if (warpedBCMask.at<int>(i, j) == 0) depths[j] = height - i;
                else break;
            }
        }
        _calculateBorderCutInPerSide(1, depths, borderCutIn);
        
        // Left
        depths.assign(height, 0);
        for (int i = 0; i < height; i++) {
            for (int j = 0; j < maxCutIn; j++) {
                if (warpedBCMask.at<int>(i, j) == 0) depths[i] = j;
                else break;
            }
        }
        _calculateBorderCutInPerSide(2, depths, borderCutIn);
        
        // Right
        depths.assign(height, 0);
        for (int i = 0; i < height; i++) {
            for (int j = width - 1; j > width - maxCutIn; j--) {
                if (warpedBCMask.at<int>(i, j) == 0) depths[i] = width - j;
                else break;
            }
        }
        _calculateBorderCutInPerSide(3, depths, borderCutIn);
        LOG_EXIT();
    }

    double _calculateTransformation(
        cv::Mat* borderCorrectionMask, 
        std::vector<std::vector<int>>& corners, 
        bool usingHough,
        std::vector<int>* borderCutIn,
        int* K, int* height, int* width
    ) {
        LOG_ENTRY();
        
        double calculatedRatio = _calculateAspectRatio(corners);
        double matchedRatio = _matchAspectRatioAndOrientation(calculatedRatio);
        
        _setHeightFromCorners(corners, matchedRatio, K, height, width);
        _calculateBorderCutIn(borderCorrectionMask, corners, usingHough, borderCutIn, *K, *height, *width);
        
        LOG_EXIT();
        return matchedRatio;
    }
    
    void _applyBorderCutInToCorners(std::vector<std::vector<int>>& corners, std::vector<int> borderCutIn) {
        LOG_ENTRY();
        
        if (!borderCutIn.empty()) {
            corners[0][0] += borderCutIn[0]; corners[2][0] += borderCutIn[1]; // top
            corners[1][0] -= borderCutIn[2]; corners[3][0] -= borderCutIn[3]; // bottom
            corners[0][1] += borderCutIn[4]; corners[1][1] += borderCutIn[5]; // left
            corners[2][1] -= borderCutIn[6]; corners[3][1] -= borderCutIn[7]; // right
        }
    }
    
    cv::Mat _transformImage(
        const cv::Mat& imageMat, 
        const std::vector<std::vector<int>>& corners,
        int height, int width
    ) {
        LOG_ENTRY();
        LOG_VAR(height);
        LOG_VAR(width);
        LOG_VAR(corners);
        for (size_t i = 0; i < corners.size(); ++i) {
            LOGD("Corner[%zu] = (%d, %d)", i, corners[i][0], corners[i][1]);
        }
        if (corners.size() != 4) {
            LOGE("Corner count != 4");
            LOG_EXIT();
            return cv::Mat();
        }

        // Source points (note: Dart swapped [row,col] vs [y,x])
        std::vector<cv::Point2f> srcPoints = {
            cv::Point2f(static_cast<float>(corners[0][1]), static_cast<float>(corners[0][0])),
            cv::Point2f(static_cast<float>(corners[1][1]), static_cast<float>(corners[1][0])),
            cv::Point2f(static_cast<float>(corners[2][1]), static_cast<float>(corners[2][0])),
            cv::Point2f(static_cast<float>(corners[3][1]), static_cast<float>(corners[3][0]))
        };
        
        // Destination points
        std::vector<cv::Point2f> dstPoints = {
            cv::Point2f(0.0f, 0.0f),
            cv::Point2f(0.0f, static_cast<float>(height)),
            cv::Point2f(static_cast<float>(width), 0.0f),
            cv::Point2f(static_cast<float>(width), static_cast<float>(height))
        };
        
        // Perspective transform matrix
        cv::Mat transformationMatrix = cv::getPerspectiveTransform(srcPoints, dstPoints);
        
        // Warp image
        cv::Mat warped;
        try {
            cv::warpPerspective(imageMat, warped, transformationMatrix, cv::Size(width, height));
        } catch (const cv::Exception& e) {
            LOGE("OpenCV exception: %s", e.what());
            LOG_EXIT();
            return cv::Mat();
        }
        
        LOG_EXIT();
        return warped;
    }
    
    bool _saveImage(const std::string& inPath, const cv::Mat& inImage) const {
        LOG_ENTRY();
        LOG_EXIT();
        return cv::imwrite(inPath, inImage);
    }

public:
    
    bool loadPhoto(const std::string& inPath) {
        LOG_ENTRY();
        photo = cv::imread(inPath, cv::IMREAD_UNCHANGED);
        if (photo.empty()) {
            LOG_EXIT();
            return false;
        }
        LOG_EXIT();
        return true;
    }
    
    void setAvailableAspectRatios(std::vector<double> inAvailableAspectRatios){
        LOG_ENTRY();
        availableAspectRatios = inAvailableAspectRatios;
        LOG_EXIT();
    }
    
    bool warpImage(
        const std::string& inWarpedPath,
        double* inOutRatioValue,
        std::vector<std::vector<int>>* inOutCorners
    ) {
        LOG_ENTRY();
        LOG_VAR(inWarpedPath);
        LOG_VAR(inOutRatioValue);
        LOG_VAR(inOutCorners);
        
        if (!inOutRatioValue || !inOutCorners || photo.empty()) {
            LOGE("inOutCorners OR inOutRatioValue is nullptr OR photo empty!");
            LOG_EXIT();
            return false;
        }
        
        cv::Mat borderCorrectionMask;
        std::vector<int> borderCutIn;

        bool usingHough = false;
        int K = (photo.rows + photo.cols) / 100;
        int height = 0;
        int width = 0;
        
        
        
        // Step 1: Detect or reuse corners
        cv::Mat prefiltered;
        if (inOutCorners->empty()) {
            // 1a. Pre-filter to isolate shape
            prefiltered = _preFilter(photo, K);
            
            // 1b. Detect edges
            cv::Mat edges = _edgeDetection(prefiltered, K);
            
            // 1c. Get document mask & border correction mask
            cv::Mat mask;
            _documentMask(edges, K, &usingHough, &mask, &borderCorrectionMask);
            LOGI("after _documentMask");
            // 1d. Detect corners
            *inOutCorners = _detectCorners(mask, K);
        }
        
        // Step 2: Calculate or reuse ratio
        if (*inOutRatioValue == 0) {
            *inOutRatioValue = _calculateTransformation(
                &borderCorrectionMask, 
                *inOutCorners, 
                usingHough,
                &borderCutIn, 
                &K, &height, &width
            );
        } else {
            _setHeightFromCorners(*inOutCorners, *inOutRatioValue, 
                &K, &height, &width);
            _calculateBorderCutIn(
                &borderCorrectionMask, 
                *inOutCorners, 
                usingHough, 
                &borderCutIn,
                K, height, width);
        }
        
        // Step 3: Apply border cut in
        _applyBorderCutInToCorners(*inOutCorners, borderCutIn);
        
        // Step 4: Perspective transform
        warped = _transformImage(photo, *inOutCorners, height, width);
        K = ((warped.rows + warped.cols) / 50);
        
        // Step 5: Save warped image
        if (!_saveImage(inWarpedPath, warped)) {
            LOG_EXIT();
            return false;
        }
        
        LOG_EXIT();
        return true;
    }
};

// ------------------ Instance Lifecycle ------------------
ImageProcessor* createProcessor() {
    LOG_ENTRY();
    LOG_EXIT();
    return new ImageProcessor();
}

void freeProcessor(ImageProcessor* inOutProcessor) {
    LOG_ENTRY();
    delete inOutProcessor;
    LOG_EXIT();
}

// ------------------ Image Operations ------------------
int processorLoadPhoto(ImageProcessor* inOutProcessor, const char* inPhotoPath) {
    LOG_ENTRY();
    if (!inOutProcessor) {
        LOG_EXIT();
        return 0;
    }
    LOG_EXIT();
    return inOutProcessor->loadPhoto(inPhotoPath) ? 1 : 0;
}

void processorSetAvailableAspectRatios(
    ImageProcessor* inOutProcessor, 
    const double* values, int32_t length
) {
    LOG_ENTRY();
    std::vector<double> availableAspectRatios;
    availableAspectRatios.assign(values, values + length);
    inOutProcessor->setAvailableAspectRatios(availableAspectRatios);
    LOG_EXIT();
}

int processorWarpImage(
    ImageProcessor* inOutProcessor,
    const char* inWarpedPath,
    double* inOutRatioValue,
    int* inOutCorners
) {
    LOG_ENTRY();
    const int cornersCount = 4;
    if (!inOutProcessor) {
        LOG_EXIT();
        return 0;
    }

    std::vector<std::vector<int>> cornersVec;
    
    // If Dart provided corners
    if (inOutCorners) {
        cornersVec.resize(cornersCount, std::vector<int>(2));
        for (int i = 0; i < cornersCount; i++) {
            cornersVec[i][0] = inOutCorners[i * 2];
            cornersVec[i][1] = inOutCorners[i * 2 + 1];
        }
    }

    bool result = inOutProcessor->warpImage(
        inWarpedPath,
        inOutRatioValue,
        &cornersVec
    );
    
    // If C++ calculated corners, return them
    if (result && inOutCorners) {
        for (int i = 0; i < cornersCount; i++) {
            inOutCorners[i * 2]     = cornersVec[i][0];
            inOutCorners[i * 2 + 1] = cornersVec[i][1];
        }
    }

    LOG_EXIT();
    return result ? 1 : 0;
}

}