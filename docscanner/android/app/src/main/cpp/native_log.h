#pragma once
#include <android/log.h>
#include <sstream>
#include <thread>
#include <type_traits>
#include <cxxabi.h> // for demangling

// Returns just the filename portion of __FILE__
#define __FILENAME__ (strrchr(__FILE__, '/') ? strrchr(__FILE__, '/') + 1 : __FILE__)
// Base log macro
#define NLOG_BASE(level, fmt, ...) \
    __android_log_print(level, "Native", "[%s:%d] %s | " fmt, \
        __FILENAME__, __LINE__, __func__, ##__VA_ARGS__)

// Levels
#define LOGI(fmt, ...) NLOG_BASE(ANDROID_LOG_INFO, fmt, ##__VA_ARGS__)
#define LOGW(fmt, ...) NLOG_BASE(ANDROID_LOG_WARN, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) NLOG_BASE(ANDROID_LOG_ERROR, fmt, ##__VA_ARGS__)
#define LOGD(fmt, ...) NLOG_BASE(ANDROID_LOG_DEBUG, fmt, ##__VA_ARGS__)

// Log function entry automatically
#define LOG_ENTRY() \
    LOGD("ENTER");// thread=%ld", (long)std::hash<std::thread::id>{}(std::this_thread::get_id()))

#define LOG_EXIT() \
    LOGD("EXIT");// thread=%ld", (long)std::hash<std::thread::id>{}(std::this_thread::get_id()))

// Helper to demangle type names (for fallback)
inline std::string demangle(const char* name) {
    int status = -1;
    char* demangled = abi::__cxa_demangle(name, nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled) ? demangled : name;
    free(demangled);
    return result;
}

// Generic pointer overload
template <typename T>
void logVarInternal(const char* name, T* ptr, const char* file, int line, const char* func) {
    if (ptr) {
        std::ostringstream oss;
        // Try to print value if possible
        if constexpr (std::is_arithmetic<T>::value) {
            oss << *ptr;
        } else {
            oss << "complex_type"; // fallback
        }
        __android_log_print(ANDROID_LOG_DEBUG, "Native", "[%s:%d] %s | %s = %s (address=%p)",
            file, line, func, name, oss.str().c_str(), (void*)ptr);
    } else {
        __android_log_print(ANDROID_LOG_DEBUG, "Native", "[%s:%d] %s | %s = nullptr",
            file, line, func, name);
    }
}

// Generic value overload (non-pointers)
template <typename T>
void logVarInternal(const char* name, const T& value, const char* file, int line, const char* func) {
    std::ostringstream oss;
    if constexpr (std::is_arithmetic<T>::value || std::is_same<T, std::string>::value) {
        oss << value;
        __android_log_print(ANDROID_LOG_DEBUG, "Native", "[%s:%d] %s | %s = %s",
            file, line, func, name, oss.str().c_str());
    } else {
        // Fallback: print type name and address
        const void* addr = static_cast<const void*>(&value);
        std::string typeName = demangle(typeid(T).name());
        __android_log_print(ANDROID_LOG_DEBUG, "Native", "[%s:%d] %s | %s = <%s> (address=%p)",
            file, line, func, name, typeName.c_str(), addr);
    }
}

// The LOG_VAR macro automatically handles pointers safely
#define LOG_VAR(var) logVarInternal(#var, var, __FILENAME__, __LINE__, __func__)