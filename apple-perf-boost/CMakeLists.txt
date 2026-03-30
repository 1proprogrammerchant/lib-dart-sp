# Apple PerfBoost — CMakeLists.txt
# Builds the C / C++ / Objective-C components.
# For the Swift layer, use Package.swift (Swift Package Manager).

cmake_minimum_required(VERSION 3.20)
project(ApplePerfBoost
    VERSION 1.0.0
    LANGUAGES C CXX OBJC OBJCXX
)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)

# ── Compiler flags ─────────────────────────────────────────────
if(APPLE)
    add_compile_options(
        -Wall -Wextra -Wpedantic
        -O2
        -ffast-math                # GPU-style fast math for CPU too
        -march=native              # Tune for the host CPU (Apple Silicon / Intel)
    )
    # Objective-C ARC
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")
    set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -fobjc-arc")
endif()

# ── Include paths ──────────────────────────────────────────────
include_directories(${CMAKE_SOURCE_DIR}/src/include)

# ── Sources ────────────────────────────────────────────────────
set(C_SOURCES
    src/cpu_boost.c
    src/perf_utils.c
)

set(CPP_SOURCES
    src/perf_engine.cpp
)

set(OBJCXX_SOURCES
    src/gpu_boost.mm
)

# ── Static library (C + C++) ──────────────────────────────────
add_library(perf_boost_c STATIC ${C_SOURCES})

add_library(perf_boost_cpp STATIC ${CPP_SOURCES})
target_link_libraries(perf_boost_cpp PRIVATE perf_boost_c)

# ── Objective-C++ GPU library ─────────────────────────────────
if(APPLE)
    add_library(perf_boost_gpu STATIC ${OBJCXX_SOURCES})
    target_link_libraries(perf_boost_gpu PRIVATE
        perf_boost_c
        "-framework Metal"
        "-framework Foundation"
    )
endif()

# ── Combined convenience library ──────────────────────────────
add_library(perf_boost INTERFACE)
target_link_libraries(perf_boost INTERFACE
    perf_boost_c
    perf_boost_cpp
)
if(APPLE)
    target_link_libraries(perf_boost INTERFACE perf_boost_gpu)
endif()

# ── Optional: small C test driver ─────────────────────────────
option(BUILD_TESTS "Build the C test driver" ON)
if(BUILD_TESTS)
    add_executable(perf_boost_test tests/test_driver.c)
    target_link_libraries(perf_boost_test PRIVATE perf_boost_c)
    if(APPLE)
        target_link_libraries(perf_boost_test PRIVATE perf_boost_gpu)
    endif()
endif()

# ── Install ────────────────────────────────────────────────────
install(TARGETS perf_boost_c perf_boost_cpp
    ARCHIVE DESTINATION lib
)
install(DIRECTORY src/include/ DESTINATION include)
if(APPLE)
    install(TARGETS perf_boost_gpu ARCHIVE DESTINATION lib)
endif()

message(STATUS "Apple PerfBoost configured (APPLE=${APPLE})")
