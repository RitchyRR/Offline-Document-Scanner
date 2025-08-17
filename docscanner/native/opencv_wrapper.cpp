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
    cv::Mat pro;
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
    cv::Mat _stretchMat(
        const cv::Mat& matIn, 
        double lowPercentile = 0.005,
        double highPercentile = 0.995, 
        double gamma = std::numeric_limits<double>::quiet_NaN()
    ) {
        LOG_ENTRY();
        cv::Mat ref;
        int height = matIn.rows;
        int width = matIn.cols;
        
        if (height > 1000 || width > 1000) {
            cv::resize(matIn, ref, cv::Size(width / 4, height / 4));
        } else {
            ref = matIn.clone();
        }
        if (ref.channels() == 3) {
            cv::cvtColor(ref, ref, cv::COLOR_BGR2GRAY);
        }
        
        // Pixels -> sorted list
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
        
        // Stretch to low / high values
        cv::Mat matOut;
        cv::normalize(
            matIn,
            matOut,
            -lowValue,
            (255 - highValue) + 255,
            cv::NORM_MINMAX
        );
        
        // Optional gamma correction
        if (!isnan(gamma)) {
            matOut = _applyGammaCorrection(matOut, gamma);
        }
        
        LOG_EXIT();
        return matOut;
    }

    cv::Mat _stretchMatF32(const cv::Mat& matF32) {
        cv::Mat out;
        cv::normalize(matF32, out, 0.0, 1.0, cv::NORM_MINMAX);
        return out;
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
        //LOG_VAR(detectedCorners);
        //LOG_VAR(xOffset);
        //LOG_VAR(yOffset);
        
        std::vector<cv::Point> edgePoints;
        cv::Mat nonZero;
        cv::findNonZero(detectedCorners, nonZero);
        
        for (int i = 0; i < nonZero.total(); ++i) {
            cv::Point p = nonZero.at<cv::Point>(i);
            edgePoints.emplace_back(p.x + xOffset, p.y + yOffset);
        }
        
        //LOG_VAR(edgePoints);
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
        
        std::vector<cv::Point> xy1 = _toPoints(detectedCorners1, 0, 0);
        std::vector<cv::Point> xy2 = _toPoints(detectedCorners2, 0, rows / 2);
        std::vector<cv::Point> xy3 = _toPoints(detectedCorners3, cols / 2, 0);
        std::vector<cv::Point> xy4 = _toPoints(detectedCorners4, cols / 2, rows / 2);
        
        LOGD("xy1 %zu",xy1.size());
        LOGD("xy2 %zu",xy2.size());
        LOGD("xy3 %zu",xy3.size());
        LOGD("xy4 %zu",xy4.size());
        
        if (!xy1.empty()) {
            outerPoints[0] = *std::max_element(xy1.begin(), xy1.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (-a.y - a.x) < (-b.y - b.x); });
        } else { fallbacks.push_back(0); outerPoints[0] = cv::Point(cols / 2 - 1, rows / 2 - 1); }
        
        if (!xy2.empty()) {
            outerPoints[1] = *std::max_element(xy2.begin(), xy2.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (a.y - a.x) < (b.y - b.x); });
        } else { fallbacks.push_back(1); outerPoints[1] = cv::Point(cols / 2 - 1, rows / 2 + 1); }

        if (!xy3.empty()) {
            outerPoints[2] = *std::max_element(xy3.begin(), xy3.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (-a.y + a.x) < (-b.y + b.x); });
        } else { fallbacks.push_back(2); outerPoints[2] = cv::Point(cols / 2 + 1, rows / 2 - 1); }
        
        if (!xy4.empty()) {
            outerPoints[3] = *std::max_element(xy4.begin(), xy4.end(),
                                            [](const cv::Point& a, const cv::Point& b){ LOG_EXIT();
        return (a.y + a.x) < (b.y + b.x); });
        } else { fallbacks.push_back(3); outerPoints[3] = cv::Point(cols / 2 + 1, rows / 2 + 1); }
        
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
        
        //LOG_VAR(outerPointsList);
        //for (size_t i = 0; i < outerPointsList.size(); ++i) {
        //    LOGD("outerPointsList[%zu] = (%d, %d)", i, outerPointsList[i][0], outerPointsList[i][1]);
        //}
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
        double matchedRatio = matchAspectRatioAndOrientation(calculatedRatio);
        
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
        //for (size_t i = 0; i < corners.size(); ++i) {
        //    LOGD("Corner[%zu] = (%d, %d)", i, corners[i][0], corners[i][1]);
        //}
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
    
    cv::Mat _documentFilterBg(const cv::Mat& src, int K) {
        // 1. Remove glow (opening)
        int k1 = std::clamp((K / 18) + 1, 3, std::numeric_limits<int>::max());
        cv::Mat kernel1 = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(k1, k1));
        
        cv::Mat bg;
        cv::morphologyEx(src, bg, cv::MORPH_OPEN, kernel1, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        
        // 2. Blur
        cv::blur(bg, bg, cv::Size((K * 2) + 1, (K * 2) + 1));
        
        // 3. Remove dark structures (closing)
        int k2 = K * 2;
        bg = _closingCircleApprox(bg, k2);
        
        return bg;
    }

    cv::Mat _proFilterBGsubtracted(const cv::Mat& warped, int K) {
        cv::Mat bg = _proFilterBG(warped, K);
        
        // Convert to F32 [0,1]
        cv::Mat warpedF32, bgF32;
        warped.convertTo(warpedF32, CV_32FC3, 1.0 / 255.0);
        bg.convertTo(bgF32, CV_32FC3, 1.0 / 255.0);
        
        // Subtract background
        cv::Mat subtracted;
        cv::addWeighted(warpedF32, 1.0, bgF32, -1.0, 0.5, subtracted);
        
        // Normalize [0,1]
        subtracted = _stretchMatF32(subtracted);
        
        // Back to 8-bit
        subtracted.convertTo(subtracted, CV_8UC3, 255.0);

        // Clip 0.5%
        subtracted = _stretchMat(subtracted, 0.005, 0.995);
        
        // HSV adjustments
        cv::Mat hsv;
        cv::cvtColor(subtracted, hsv, cv::COLOR_BGR2HSV);
        std::vector<cv::Mat> hsvChannels;
        cv::split(hsv, hsvChannels);

        int medianBrightness = _medianBrightness(hsvChannels[2]);
        int highVal = 255;
        int lowVal = 0;

        if (medianBrightness > 155) {
            highVal = medianBrightness - static_cast<int>((256 - medianBrightness) * 1.5);
        } else if (medianBrightness < 100) {
            lowVal = medianBrightness - medianBrightness / 2;
        }

        hsvChannels[2] = _stretchMatValues(hsvChannels[2], lowVal, highVal, std::nullopt);
        hsvChannels[1] = _stretchMatValues(hsvChannels[1], 20, 255, std::nullopt);

        cv::merge(hsvChannels, hsv);
        cv::cvtColor(hsv, subtracted, cv::COLOR_HSV2BGR);

        // Median blur on saturation
        try {
            int k1 = 3;
            cv::cvtColor(subtracted, hsv, cv::COLOR_BGR2HSV);
            cv::split(hsv, hsvChannels);
            
            cv::Mat satBlur;
            cv::medianBlur(hsvChannels[1], satBlur, k1);
            cv::min(satBlur, hsvChannels[1], hsvChannels[1]);
            
            cv::merge(hsvChannels, hsv);
            cv::cvtColor(hsv, subtracted, cv::COLOR_HSV2BGR);
        }
        catch (...) {
            LOGW("Warning in _proFilterBGsubtracted: medianBlur on saturation failed");
        }
        
        return subtracted;
    }
    
    cv::Mat _proFilterBG(const cv::Mat& warped, int K) {
        cv::Mat bg = warped.clone();
        
        // 1. Remove glow (Opening)
        int k1 = std::clamp((K / 30) + 1, 3, std::numeric_limits<int>::max());
        cv::Mat kernel1 = cv::getStructuringElement(cv::MORPH_CROSS, cv::Size(k1, k1));
        cv::morphologyEx(bg, bg, cv::MORPH_OPEN, kernel1, cv::Point(-1, -1), 2, cv::BORDER_REPLICATE);
        
        // 2. Median blur
        int kernelSize = (K * 2) + 1;
        kernelSize = std::clamp(kernelSize, 3, std::numeric_limits<int>::max());
        
        bool medianBlurSucceeded = false;
        while (!medianBlurSucceeded) {
            try {
                cv::medianBlur(bg, bg, kernelSize);
                medianBlurSucceeded = true;
            }
            catch (...) {
                if (kernelSize == 3) break;
                kernelSize = std::clamp(((static_cast<int>(kernelSize * 0.9) / 2) * 2 + 1), 3, std::numeric_limits<int>::max());
            }
        }
        
        // 3. Remove dark structures (Closing)
        bg = _closingCircleApprox(bg, K * 2);

        // 4. HSV: V channel max(bg, warpedV)
        cv::Mat bgHSV, warpedHSV;
        cv::cvtColor(bg, bgHSV, cv::COLOR_BGR2HSV);
        cv::cvtColor(warped, warpedHSV, cv::COLOR_BGR2HSV);
        
        std::vector<cv::Mat> bgChannels, warpedChannels;
        cv::split(bgHSV, bgChannels);
        cv::split(warpedHSV, warpedChannels);
        
        bg = _closingCircleApprox(bg, K / 9);
        bgChannels[2] = cv::max(bgChannels[2], warpedChannels[2]);

        cv::merge(bgChannels, bgHSV);
        cv::cvtColor(bgHSV, bg, cv::COLOR_HSV2BGR);
        
        return bg;
    }

    int _medianBrightness(const cv::Mat& mat) {
        cv::Mat ref = mat;
        if (ref.rows > 1000 || ref.cols > 1000) {
            cv::resize(ref, ref, cv::Size(ref.cols / 4, ref.rows / 4));
        }
        if (ref.channels() == 3) {
            cv::cvtColor(ref, ref, cv::COLOR_BGR2GRAY);
        }
        
        std::vector<uchar> pixels;
        pixels.assign(ref.data, ref.data + ref.total());
        std::nth_element(pixels.begin(), pixels.begin() + pixels.size() / 2, pixels.end());
        return pixels[pixels.size() / 2];
    }

    cv::Mat _stretchMatValues(const cv::Mat& mat, int lowValue, int highValue, std::optional<double> gamma) {
        cv::Mat out;
        cv::normalize(mat, out, -(double)lowValue, (255.0 - (double)highValue) + 255.0, cv::NORM_MINMAX);
        if (gamma.has_value()) {
            out = _applyGammaCorrection(out, gamma.value());
        }
        return out;
    }

    cv::Mat _correctBorder(const cv::Mat& imIn, int K) {
        const int whiteThreshold = 254;
        cv::Mat borderCorrect = imIn.clone();
        
        const int maxBorderSize = std::clamp(static_cast<int>(K * 0.3), 1, std::numeric_limits<int>::max());
        
        // Convert to grayscale for threshold checks
        cv::Mat reference;
        cv::cvtColor(borderCorrect, reference, cv::COLOR_BGR2GRAY);
        
        int height = borderCorrect.rows;
        int width = borderCorrect.cols;
        
        // Top border
        for (int j = 0; j < width; j++) {
            int whiteAt = 0;
            for (; whiteAt <= maxBorderSize; whiteAt++) {
                if (reference.at<uchar>(whiteAt, j) >= whiteThreshold) {
                    break;
                }
            }
            if (whiteAt > maxBorderSize) continue;

            for (int i = whiteAt; i >= 0; i--) {
                borderCorrect.at<cv::Vec3b>(i, j) = cv::Vec3b(255, 255, 255);
            }
        }

        cv::cvtColor(borderCorrect, reference, cv::COLOR_BGR2GRAY);
        // Bottom border
        for (int j = 0; j < width; j++) {
            int whiteAt = height - 1;
            for (; whiteAt >= height - maxBorderSize - 1; whiteAt--) {
                if (reference.at<uchar>(whiteAt, j) >= whiteThreshold) {
                    break;
                }
            }
            if (whiteAt < height - maxBorderSize - 1) continue;

            for (int i = whiteAt; i < height; i++) {
                borderCorrect.at<cv::Vec3b>(i, j) = cv::Vec3b(255, 255, 255);
            }
        }

        cv::cvtColor(borderCorrect, reference, cv::COLOR_BGR2GRAY);
        // Left border
        for (int i = 0; i < height; i++) {
            int whiteAt = 0;
            for (; whiteAt <= maxBorderSize; whiteAt++) {
                if (reference.at<uchar>(i, whiteAt) >= whiteThreshold) {
                    break;
                }
            }
            if (whiteAt > maxBorderSize) continue;
            
            for (int j = whiteAt; j >= 0; j--) {
                borderCorrect.at<cv::Vec3b>(i, j) = cv::Vec3b(255, 255, 255);
            }
        }

        cv::cvtColor(borderCorrect, reference, cv::COLOR_BGR2GRAY);
        // Right border
        for (int i = 0; i < height; i++) {
            int whiteAt = width - 1;
            for (; whiteAt >= width - maxBorderSize - 1; whiteAt--) {
                if (reference.at<uchar>(i, whiteAt) >= whiteThreshold) {
                    break;
                }
            }
            if (whiteAt < width - maxBorderSize - 1) continue;
            
            for (int j = whiteAt; j < width; j++) {
                borderCorrect.at<cv::Vec3b>(i, j) = cv::Vec3b(255, 255, 255);
            }
        }
        
        return borderCorrect;
    }

    cv::Mat _sharpenImage(const cv::Mat& warped, double sharpeningStrength, int K) {
        // Build 5x5 kernel
        float kernelData[25] = {
            0.00, -0.05, -0.05, -0.05,  0.00,
            -0.05, -0.20, -0.20, -0.20, -0.05,
            -0.05, -0.20,  0.00, -0.20, -0.05,
            -0.05, -0.20, -0.20, -0.20, -0.05,
            0.00, -0.05, -0.05, -0.05,  0.00
        };
        cv::Mat sharpenKernel(5, 5, CV_32FC1, kernelData);
        
        sharpenKernel *= static_cast<float>(sharpeningStrength);
        
        // Adjust center so sum(kernel) = 1
        double sumKernel = cv::sum(sharpenKernel)[0];
        float sharpenKernelCenter = static_cast<float>(-sumKernel + 1.0);
        sharpenKernel.at<float>(2, 2) = sharpenKernelCenter;

        // Apply filter
        cv::Mat sharpened;
        cv::filter2D(warped, sharpened, -1, sharpenKernel, cv::Point(-1, -1), 0, cv::BORDER_REPLICATE);
        
        // Apply sharpening only to text/fine lines
        sharpened = _applyFilterToText(warped, sharpened, K);
        
        return sharpened;
    }

    cv::Mat _applyFilterToText(
        const cv::Mat& imIn,
        const cv::Mat& filteredIn, 
        int K,
        bool aroundText = true,
        bool applyToText = true,
        double thresh = 15.0,
        double textFineness = 22.0
    ) {
        int k = ((static_cast<int>(K / textFineness) / 2) * 2 + 1);
        k = std::clamp(k, 3, std::numeric_limits<int>::max());
        
        // Remove fine lines / text (closing operation)
        cv::Mat noText = _closingCircleApprox(imIn, k);
        
        // Difference between original and "no text" version
        cv::Mat diff;
        cv::absdiff(imIn, noText, diff);
        
        if (aroundText) {
            cv::Mat kernel2 = cv::getStructuringElement(cv::MORPH_RECT, cv::Size(3, 3));
            cv::morphologyEx(diff, diff, cv::MORPH_DILATE, kernel2, cv::Point(-1, -1), 1, cv::BORDER_REPLICATE);
        }
        
        // Create binary masks from difference
        cv::Mat textMask, maskInv;
        cv::threshold(diff, textMask, thresh, 1.0, cv::THRESH_BINARY);
        cv::threshold(diff, maskInv, thresh, 1.0, cv::THRESH_BINARY_INV);
        
        cv::Mat result;
        if (applyToText) {
            // Keep filtered where text is, original elsewhere
            cv::add(filteredIn.mul(textMask), imIn.mul(maskInv), result);
        } else {
            // Keep filtered where NOT text, original on text
            cv::add(filteredIn.mul(maskInv), imIn.mul(textMask), result);
        }
        
        return result;
    }

    cv::Mat _matchColor(const cv::Mat& mat, const cv::Mat& sample) {
        cv::Vec3b orig = _medianRGB(mat);
        cv::Vec3b proc = _medianRGB(sample);
        
        double eps = std::numeric_limits<double>::min();
        double rRatio = std::min(static_cast<double>(orig[2]) / std::max(static_cast<double>(proc[2]), eps), static_cast<double>(FLT_MAX));
        double gRatio = std::min(static_cast<double>(orig[1]) / std::max(static_cast<double>(proc[1]), eps), static_cast<double>(FLT_MAX));
        double bRatio = std::min(static_cast<double>(orig[0]) / std::max(static_cast<double>(proc[0]), eps), static_cast<double>(FLT_MAX));
        
        // Split sample channels
        std::vector<cv::Mat> sampleChannels;
        cv::split(sample, sampleChannels);
        
        // Convert to double precision, scale, then back
        cv::Mat r, g, b;
        sampleChannels[2].convertTo(r, CV_64F, 1.0 / 255.0);
        sampleChannels[1].convertTo(g, CV_64F, 1.0 / 255.0);
        sampleChannels[0].convertTo(b, CV_64F, 1.0 / 255.0);
        
        r *= rRatio;
        g *= gRatio;
        b *= bRatio;

        // Merge channels and convert back to 8-bit
        std::vector<cv::Mat> merged = { b, g, r };
        cv::Mat result;
        cv::merge(merged, result);
        result.convertTo(result, CV_8UC3, 255.0);
        
        return result;
    }
    
    cv::Vec3b _medianRGB(const cv::Mat& mat) {
        std::vector<cv::Mat> channels;
        cv::split(mat, channels);
        
        // Flatten channel to vector
        std::vector<uchar> r, g, b;
        r.assign(channels[2].datastart, channels[2].dataend);
        g.assign(channels[1].datastart, channels[1].dataend);
        b.assign(channels[0].datastart, channels[0].dataend);
        
        std::sort(r.begin(), r.end());
        std::sort(g.begin(), g.end());
        std::sort(b.begin(), b.end());
        
        size_t mid = r.size() / 2;
        return cv::Vec3b(b[mid], g[mid], r[mid]);
    }

public:
    
    bool loadPhoto(const std::string& inPath) {
        LOG_ENTRY();
        photo = cv::imread(inPath);
        if (photo.empty()) {
            LOG_EXIT();
            return false;
        }
        LOG_EXIT();
        return true;
    }

    bool loadWarped(const std::string& inPath) {
        LOG_ENTRY();
        warped = cv::imread(inPath);
        if (warped.empty()) {
            LOG_EXIT();
            return false;
        }
        LOG_EXIT();
        return true;
    }

    bool loadPro(const std::string& inPath) {
        LOG_ENTRY();
        pro = cv::imread(inPath);
        if (pro.empty()) {
            LOG_EXIT();
            return false;
        }
        LOG_EXIT();
        return true;
    }

    bool savePhoto(const std::string& inPath) {
        LOG_ENTRY();
        bool success = cv::imwrite(inPath, photo);
        LOG_EXIT();
        return success;
    }
    
    void setAvailableAspectRatios(std::vector<double> inAvailableAspectRatios){
        LOG_ENTRY();
        availableAspectRatios = inAvailableAspectRatios;
        LOG_EXIT();
    }

    double matchAspectRatioAndOrientation(double inCalculatedRatio) {
        LOG_ENTRY();
        
        double matchingValue = std::sqrt(2.0);
        bool portrait = true;
        double portraitValue = inCalculatedRatio;
        
        if (inCalculatedRatio < 1.0) {
            portraitValue = 1.0 / inCalculatedRatio;
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
        this->warped = _transformImage(photo, *inOutCorners, height, width);
        K = ((warped.rows + warped.cols) / 50);
        
        // Step 5: Save warped image
        if (!cv::imwrite(inWarpedPath, warped)) {
            LOG_EXIT();
            return false;
        }
        
        LOG_EXIT();
        return true;
    }

    bool contrastFilter(const std::string& inContrastPath) {
        try {
            if (warped.empty()) {
                LOGE("'warped' image is empty");
                return false;
            }
            
            // Apply contrast
            cv::Mat stretched = _stretchMat(
                warped,
                0.002,
                0.998
            );
            
            // Save image
            if (!cv::imwrite(inContrastPath, stretched)) {
                LOGE("Failed to write contrast image to %s", inContrastPath.c_str());
                return false;
            }
            
            return true;
        } catch (const std::exception& e) {
            LOGE("Exception in contrastFilter: %s", e.what());
            return false;
        } catch (...) {
            LOGE("Unknown error in contrastFilter");
            return false;
        }
    }

    bool documentFilter(const std::string& inProColorFilterPath) {
        try {
            // "warped" is assumed to be a member variable set earlier
            if (warped.empty()) {
                LOGE("No warped image loaded before isolateAndSubtractBGSimple");
                return false;
            }
            int K = (warped.rows + warped.cols) / 50;

            cv::Mat bg = _documentFilterBg(warped, K);

            // Subtract background
            cv::Mat subtracted;
            cv::addWeighted(warped, 1.0, bg, -1.0, 255.0, subtracted);

            // Stretch result
            subtracted = _stretchMat(
                subtracted,
                0.005, // lowPercentile
                0.995  // highPercentile
            );

            if (!cv::imwrite(inProColorFilterPath, subtracted)) {
                LOGE("Failed to write BG-subtracted image to %s", inProColorFilterPath.c_str());
                return false;
            }

            return true;
        }
        catch (const std::exception& e) {
            LOGE("Exception in isolateAndSubtractBGSimple: %s", e.what());
            return false;
        }
        catch (...) {
            LOGE("Unknown error in isolateAndSubtractBGSimple");
            return false;
        }
    }

    bool proFilter(const std::string& inProColorFilterPath) {
        try {
            if (warped.empty()) {
                LOGE("No warped image loaded before proFilter");
                return false;
            }
            int K = (warped.rows + warped.cols) / 50;
            
            // 5. Background subtraction
            cv::Mat processed2 = _proFilterBGsubtracted(warped, K);
            
            // 6. Border correction
            processed2 = _correctBorder(processed2, K);
            
            // 7. Sharpen
            processed2 = _sharpenImage(processed2, 0.5, K);
            
            if (!cv::imwrite(inProColorFilterPath, processed2)) {
                LOGE("Failed to write ProFilter image to %s", inProColorFilterPath.c_str());
                return false;
            }
            
            this->pro = processed2;
            
            return true;
        }
        catch (const std::exception& e) {
            LOGE("Exception in proFilter: %s", e.what());
            return false;
        }
        catch (...) {
            LOGE("Unknown error in proFilter");
            return false;
        }
    }

    bool proColorFilter(const char* inProColorFilterPath) {
        try {
            // Make sure we have both warped and pro available
            if (warped.empty() || pro.empty()) {
                LOGE("proColorFilter: warped or pro image is empty");
                return false;
            }
            
            // Apply filterImage3 logic
            cv::Mat colorMatched = _matchColor(warped, pro);
            
            // Save result
            if (!cv::imwrite(inProColorFilterPath, colorMatched)) {
                LOGE("proColorFilter: failed to write image");
                return false;
            }
            
            return true;
        } catch (const cv::Exception& e) {
            LOGE("proColorFilter exception: %s", e.what());
            return false;
        }
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
    LOG_EXIT();
    delete inOutProcessor;
}

// ------------------ Image Operations ------------------
int processorImportPhoto(
    ImageProcessor* inOutProcessor, 
    const char* inSourcePath,
    const char* inPhotoPath
) {
    LOG_ENTRY();
    LOG_VAR(inSourcePath);
    if (!inOutProcessor || !inSourcePath || !inPhotoPath) {
        LOG_EXIT();
        return 0;
    }
    
    bool success = inOutProcessor->loadPhoto(inSourcePath);
    success = success && (!inPhotoPath || inPhotoPath[0] == '\0') ? true 
        : inOutProcessor->savePhoto(inPhotoPath);
    
    LOG_EXIT();
    return success ? 1 : 0;
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
    int32_t* inOutCorners,
    bool passingInCorners
) {
    LOG_ENTRY();
    LOG_VAR(inWarpedPath);
    LOG_VAR(inOutRatioValue);
    LOG_VAR(inOutCorners);
    LOG_VAR(passingInCorners);
    
    if (!inOutProcessor || !inWarpedPath || !inOutRatioValue || !inOutCorners) { 
        LOG_EXIT(); 
        return 0; 
    }
    
    const int cornersCount = 4;
    std::vector<std::vector<int>> cornersVec;
    if (passingInCorners) {
        cornersVec.resize(cornersCount, std::vector<int>(2));
        for (int i = 0; i < cornersCount; i++) {
            cornersVec[i][0] = inOutCorners[i * 2];
            cornersVec[i][1] = inOutCorners[i * 2 + 1];
        }
    }
    
    bool success = inOutProcessor->warpImage(
        inWarpedPath,
        inOutRatioValue,
        &cornersVec
    );
    if (!success) { LOG_EXIT(); return 0; }

    LOG_VAR(inOutRatioValue);
    LOG_VAR(cornersVec);
    for (size_t i = 0; i < cornersVec.size(); i++) {
        LOGD("cornersVec[%zu] = (%d, %d)", i, cornersVec[i][0], cornersVec[i][1]);
    }
    
    for (int i = 0; i < cornersCount; i++) {
        inOutCorners[i * 2]     = cornersVec[i][0];
        inOutCorners[i * 2 + 1] = cornersVec[i][1];
    }

    LOG_VAR(inOutCorners);
    for (size_t i = 0; i < cornersCount*2; i++) {
        LOGD("inOutCorners[%zu] = %d", i, inOutCorners[i]);
    }
    LOG_EXIT();
    return 1;
}

int processorContrastFilter(
    ImageProcessor* inOutProcessor,
    const char* inContrastPath
) {
    LOG_ENTRY();
    LOG_VAR(inContrastPath);
    
    if (!inOutProcessor || !inContrastPath) {
        LOG_EXIT();
        return 0;
    }
    
    bool success = inOutProcessor->contrastFilter(inContrastPath);
    
    LOG_EXIT();
    return success ? 1 : 0;
}

int processorDocumentFilter(
    ImageProcessor* inOutProcessor,
    const char* inBGSubtractedPath
) {
    LOG_ENTRY();
    LOG_VAR(inBGSubtractedPath);

    if (!inOutProcessor || !inBGSubtractedPath) {
        LOG_EXIT();
        return 0;
    }

    bool success = inOutProcessor->documentFilter(inBGSubtractedPath);

    LOG_EXIT();
    return success ? 1 : 0;
}

int processorProFilter(
    ImageProcessor* inOutProcessor,
    const char* inProFilterPath
) {
    LOG_ENTRY();
    LOG_VAR(inProFilterPath);
    
    if (!inOutProcessor || !inProFilterPath) {
        LOG_EXIT();
        return 0;
    }
    
    bool success = inOutProcessor->proFilter(inProFilterPath);
    
    LOG_EXIT();
    return success ? 1 : 0;
}

int processorProColorFilter(
    ImageProcessor* inOutProcessor,
    const char* inProColorFilterPath
) {
    LOG_ENTRY();
    LOG_VAR(inProColorFilterPath);

    if (!inOutProcessor || !inProColorFilterPath) {
        LOG_EXIT();
        return 0;
    }

    bool success = inOutProcessor->proColorFilter(inProColorFilterPath);
    
    LOG_EXIT();
    return success ? 1 : 0;
}

// Other image processing:

int rotateImage(
    const char* inSourcePath,
    const char* inRotatedPath,
    int inAngle
) {
    LOG_ENTRY();
    LOG_VAR(inAngle);
    
    if (!inSourcePath || !inRotatedPath) {
        LOG_EXIT();
        return 0;
    }
    
    // read
    cv::Mat source = cv::imread(inSourcePath);
    if (source.empty()) {
        LOG_EXIT();
        return 0;
    }

    // rotate
    cv::Mat rotated;
    if (inAngle == 90) {
        cv::rotate(source, rotated, cv::ROTATE_90_CLOCKWISE);
    } else if (inAngle == 270) {
        cv::rotate(source, rotated, cv::ROTATE_90_COUNTERCLOCKWISE);
    } else if (inAngle == 180){
        cv::rotate(source, rotated, cv::ROTATE_180);
    } else {
        rotated = source;
    }
    
    // write
    if (!cv::imwrite(inRotatedPath, rotated)) {
        LOGE("rotateImage: failed to write image");
        return 0;
    }
    
    LOG_EXIT();
    return 1;
}

int scaleImageToWidth(
    const char* inSourcePath,
    const char* inScaledPath,
    int inNewWidth,
    int* outNewHeight
) {
    LOG_ENTRY();
    LOG_VAR(inNewWidth);
    
    if (!inSourcePath || !inScaledPath || !outNewHeight) {
        LOG_EXIT();
        return 0;
    }
    
    // Read image
    cv::Mat source = cv::imread(inSourcePath);
    if (source.empty()) {
        LOG_EXIT();
        return 0;
    }
    
    // Compute new height maintaining aspect ratio
    int newHeight = static_cast<int>(source.rows * static_cast<double>(inNewWidth) / source.cols);
    
    cv::Mat scaled;
    try {
        cv::resize(
            source,
            scaled,
            cv::Size(inNewWidth, newHeight),
            0,
            0,
            cv::INTER_LINEAR
        );
    } catch (const cv::Exception& e) {
        LOGE("scaleImageToWidth: exception during resize: %s", e.what());
        //scaled = cv::Mat::zeros(newHeight, inNewWidth, CV_8UC3);
        return 0;
    }
    
    // Write output image
    if (!cv::imwrite(inScaledPath, scaled)) {
        LOGE("scaleImageToWidth: failed to write image");
        return 0;
    }
    
    *outNewHeight = newHeight;
    LOG_EXIT();
    return 1;
}

int scaleImageToMaxSize(
    const char* inSourcePath,
    const char* inScaledPath,
    int inMaxSize
) {
    LOG_ENTRY();
    LOG_VAR(inMaxSize);
    
    if (!inSourcePath || !inScaledPath) {
        LOG_EXIT();
        return 0;
    }
    
    // Read image
    cv::Mat source = cv::imread(inSourcePath);
    if (source.empty()) {
        LOG_EXIT();
        return 0;
    }
    
    int srcWidth = source.cols;
    int srcHeight = source.rows;
    // return if scaling not needed
    if (srcWidth < inMaxSize && srcHeight < inMaxSize) {
      return 0;
    }
    // Compute new width
    int newWidth = inMaxSize;
    if (srcWidth < srcHeight) {
      newWidth = inMaxSize * srcWidth / srcHeight;
    }
    
    int newHeight;
    int success = scaleImageToWidth(inSourcePath, inScaledPath, newWidth, &newHeight);
    
    LOG_EXIT();
    return success;
}

int processorMatchAspectRatioAndOrientation(
    ImageProcessor* inOutProcessor,
    double inCalculatedRatio,
    double* outMatchingRatio
) {
    LOG_ENTRY();
    if (!inOutProcessor || !outMatchingRatio) {
        LOG_EXIT();
        return 0;
    }
    
    *outMatchingRatio = inOutProcessor->matchAspectRatioAndOrientation(inCalculatedRatio);
    
    LOG_EXIT();
    return 1;
}

int processorLoadPhoto (
    ImageProcessor* inOutProcessor,
    const char* inSourcePath
) {
    LOG_ENTRY();
    LOG_VAR(inSourcePath);
    if (!inOutProcessor || !inSourcePath) {
        LOG_EXIT();
        return 0;
    }
    
    bool success = inOutProcessor->loadPhoto(inSourcePath);
    
    LOG_EXIT();
    return success ? 1 : 0;
}

int processorLoadWarped (
    ImageProcessor* inOutProcessor,
    const char* inSourcePath
) {
    LOG_ENTRY();
    LOG_VAR(inSourcePath);
    if (!inOutProcessor || !inSourcePath) {
        LOG_EXIT();
        return 0;
    }
    
    bool success = inOutProcessor->loadWarped(inSourcePath);
    
    LOG_EXIT();
    return success ? 1 : 0;
}

int processorLoadPro (
    ImageProcessor* inOutProcessor,
    const char* inSourcePath
) {
    LOG_ENTRY();
    LOG_VAR(inSourcePath);
    if (!inOutProcessor || !inSourcePath) {
        LOG_EXIT();
        return 0;
    }
    
    bool success = inOutProcessor->loadPro(inSourcePath);
    
    LOG_EXIT();
    return success ? 1 : 0;
}

}