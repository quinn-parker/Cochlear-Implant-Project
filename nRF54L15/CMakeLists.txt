# SPDX-License-Identifier: Apache-2.0
# Cochlear Implant Project - DSP Applications
# Target: nRF54L15

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
project(cochlear_implant_dsp)

# Build option: select which application to build
# BUILD_APP options:
#   "hearing_aid_dsp" - Hearing Aid DSP Signal Processor (default)
#   "fft_analyzer"    - FFT Waveform Analyzer
#   "pdm_test"        - PDM Microphone Test
set(BUILD_APP "hearing_aid_dsp" CACHE STRING "Application to build")
set_property(CACHE BUILD_APP PROPERTY STRINGS "hearing_aid_dsp" "fft_analyzer" "pdm_test")

if(BUILD_APP STREQUAL "hearing_aid_dsp")
    message(STATUS "Building Hearing Aid DSP Processor")
    target_sources(app PRIVATE
        src/hearing_aid_dsp.c
    )
elseif(BUILD_APP STREQUAL "fft_analyzer")
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

# Math library for FFT/DSP calculations
target_link_libraries(app PRIVATE m)
