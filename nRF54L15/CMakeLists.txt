# SPDX-License-Identifier: Apache-2.0
# Cochlear Implant Project - FFT Waveform Analyzer v1.0
# Target: nRF54L15

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(fft_waveform_analyzer)

# Build option: select which application to build
# Set BUILD_FFT_ANALYZER=ON to build the FFT waveform analyzer (default)
# Set BUILD_FFT_ANALYZER=OFF to build the original PDM microphone test
option(BUILD_FFT_ANALYZER "Build FFT Waveform Analyzer instead of PDM test" ON)

if(BUILD_FFT_ANALYZER)
    message(STATUS "Building FFT Waveform Analyzer v1.0")
    target_sources(app PRIVATE
        src/fft_waveform_v1.c
    )
else()
    message(STATUS "Building PDM Microphone Test")
    target_sources(app PRIVATE
        src/main.c
    )
endif()

# Math library for FFT calculations
target_link_libraries(app PRIVATE m)
