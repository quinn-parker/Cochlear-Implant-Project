/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cochlear Implant Project - Hearing Aid DSP Signal Processor
 * Target: nRF54L15
 *
 * Advanced DSP processing pipeline:
 * - Spectral noise reduction (Wiener filtering / spectral subtraction)
 * - 12-band dynamic range compression (WDRC) with per-band MPO
 * - Automatic Gain Control (AGC)
 * - Configurable high-frequency emphasis
 * - Runtime configuration via UART and BLE
 *
 * Serial/BLE Protocol:
 * Audio:  'P' + 2-byte length (LE) + 16-bit samples (LE)
 * Config: 'W'/'w'/'G'/'R'/'S' + 2-byte length (LE) + payload + checksum
 * Output: 'R' + 2-byte length (LE) + processed 16-bit samples (LE)
 * ACK/NACK: 'A'/'N' + payload
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/sys/printk.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

LOG_MODULE_REGISTER(hearing_aid_dsp, LOG_LEVEL_INF);

/*
 * =============================================================================
 * DSP Configuration
 * =============================================================================
 */

#define SAMPLE_RATE_HZ          16000
#define FRAME_SIZE              256
#define FFT_SIZE                256
#define HOP_SIZE                128
#define NUM_COMPRESSION_BANDS   12
#define MAX_INPUT_SAMPLES       2048
#define NOISE_ESTIMATE_FRAMES   10

#define FIRMWARE_VERSION_MAJOR  2
#define FIRMWARE_VERSION_MINOR  0
#define FIRMWARE_VERSION_PATCH  0

#ifndef M_PI
#define M_PI 3.14159265358979323846f
#endif

/*
 * =============================================================================
 * Wire Protocol Structures (shared with host application)
 * =============================================================================
 * All multi-byte fields are little-endian. Floats are IEEE 754 32-bit.
 */

/* Per-channel configuration as sent over UART/BLE (24 bytes packed) */
typedef struct __attribute__((packed)) {
    float gain_db;        /* -20 to +60 dB */
    float threshold_db;   /* -60 to 0 dB */
    float ratio;          /* 1.0 to 10.0 */
    float attack_ms;      /* 1 to 100 ms */
    float release_ms;     /* 10 to 500 ms */
    float mpo_db_spl;     /* 80 to 130 dB SPL */
} channel_config_wire_t;

/* Global configuration (20 bytes packed) */
typedef struct __attribute__((packed)) {
    float master_volume_db;           /* -60 to 0 dB */
    uint8_t mute;                     /* 0 or 1 */
    uint8_t noise_reduction_enabled;  /* 0 or 1 */
    float nr_strength;                /* 0.0 to 1.0 */
    uint8_t hf_emphasis_enabled;      /* 0 or 1 */
    float hf_emphasis_start_freq;     /* Hz */
    float hf_emphasis_max_db;         /* dB */
    uint8_t padding;
} global_config_wire_t;

/* Status response */
typedef struct __attribute__((packed)) {
    uint8_t firmware_major;
    uint8_t firmware_minor;
    uint8_t firmware_patch;
    uint8_t num_channels;
    uint16_t sample_rate;
    uint16_t fft_size;
    float agc_gain_db;
    uint8_t noise_estimated;
    uint8_t processing_enabled;
} status_wire_t;

/* Protocol commands */
#define CMD_WRITE_FULL_CONFIG   'W'  /* Host->Device: 12 x channel_config_wire_t */
#define CMD_WRITE_SINGLE_CHAN   'w'  /* Host->Device: 1B index + channel_config_wire_t */
#define CMD_WRITE_GLOBAL        'G'  /* Host->Device: global_config_wire_t */
#define CMD_READ_CONFIG         'R'  /* Host->Device: empty (request config readback) */
#define CMD_READ_CONFIG_RESP    'r'  /* Device->Host: full config response */
#define CMD_READ_STATUS         'S'  /* Host->Device: empty */
#define CMD_READ_STATUS_RESP    's'  /* Device->Host: status_wire_t */
#define CMD_ACK                 'A'  /* Device->Host: 1B echoed cmd */
#define CMD_NACK                'N'  /* Device->Host: 1B cmd + 1B error */
#define CMD_PROCESS_AUDIO       'P'  /* Host->Device: audio data (existing) */

/* Config buffer for receiving config commands */
#define CONFIG_BUFFER_SIZE      512
static uint8_t config_rx_buffer[CONFIG_BUFFER_SIZE];
static volatile size_t config_rx_pos = 0;
static volatile size_t config_rx_expected = 0;
static volatile uint8_t config_rx_cmd = 0;

/*
 * =============================================================================
 * Runtime Configuration (mutable at runtime via protocol)
 * =============================================================================
 */

typedef struct {
    channel_config_wire_t channels[NUM_COMPRESSION_BANDS];
    global_config_wire_t global;
} runtime_config_t;

static runtime_config_t runtime_config;

/* Default channel center frequencies for 12 bands (Hz) */
static const float channel_center_freqs[NUM_COMPRESSION_BANDS] = {
    200.0f, 315.0f, 500.0f, 800.0f, 1000.0f, 1500.0f,
    2000.0f, 3000.0f, 4000.0f, 5000.0f, 6000.0f, 7500.0f
};

/* Default bin boundaries for 256-pt FFT at 16kHz (62.5 Hz/bin) */
static const uint16_t default_low_bins[NUM_COMPRESSION_BANDS] = {
    1, 4, 6, 10, 14, 20, 28, 36, 52, 68, 84, 104
};
static const uint16_t default_high_bins[NUM_COMPRESSION_BANDS] = {
    4, 6, 10, 14, 20, 28, 36, 52, 68, 84, 104, 128
};

static void init_default_runtime_config(void)
{
    /* Master / global defaults */
    runtime_config.global.master_volume_db = 0.0f;
    runtime_config.global.mute = 0;
    runtime_config.global.noise_reduction_enabled = 1;
    runtime_config.global.nr_strength = 0.5f;
    runtime_config.global.hf_emphasis_enabled = 1;
    runtime_config.global.hf_emphasis_start_freq = 1500.0f;
    runtime_config.global.hf_emphasis_max_db = 12.0f;
    runtime_config.global.padding = 0;

    /* Per-channel defaults (clinical starting point) */
    const float default_gains[NUM_COMPRESSION_BANDS] =
        { 6.0f, 4.0f, 2.0f, 0.0f, 0.0f, 2.0f, 4.0f, 6.0f, 6.0f, 4.0f, 3.0f, 2.0f };
    const float default_thresholds[NUM_COMPRESSION_BANDS] =
        { -40.0f, -40.0f, -38.0f, -36.0f, -35.0f, -34.0f, -32.0f, -30.0f, -30.0f, -32.0f, -34.0f, -35.0f };
    const float default_ratios[NUM_COMPRESSION_BANDS] =
        { 1.4f, 1.5f, 1.8f, 2.0f, 2.2f, 2.5f, 2.8f, 3.0f, 2.8f, 2.5f, 2.2f, 2.0f };

    for (int i = 0; i < NUM_COMPRESSION_BANDS; i++) {
        runtime_config.channels[i].gain_db = default_gains[i];
        runtime_config.channels[i].threshold_db = default_thresholds[i];
        runtime_config.channels[i].ratio = default_ratios[i];
        runtime_config.channels[i].attack_ms = 5.0f;
        runtime_config.channels[i].release_ms = 50.0f;
        runtime_config.channels[i].mpo_db_spl = 110.0f;
    }
}

/*
 * =============================================================================
 * Compression Band Working State (derived from runtime_config)
 * =============================================================================
 */

typedef struct {
    uint16_t low_bin;
    uint16_t high_bin;
    float center_freq;
    float threshold_db;
    float ratio;
    float attack_coeff;   /* computed from attack_ms */
    float release_coeff;  /* computed from release_ms */
    float gain_db;
    float mpo_db_spl;
    float envelope;
} compression_band_t;

static compression_band_t compression_bands[NUM_COMPRESSION_BANDS];

/*
 * =============================================================================
 * Data Structures
 * =============================================================================
 */

typedef struct {
    float real;
    float imag;
} complex_t;

typedef struct {
    float noise_floor[FFT_SIZE / 2];
    float signal_estimate[FFT_SIZE / 2];
    uint32_t noise_frames_collected;
    bool noise_estimated;
} noise_reduction_state_t;

typedef struct {
    float agc_gain;
    float target_level_db;
    float max_gain_db;
    float min_gain_db;
    float attack_coeff;
    float release_coeff;
} agc_state_t;

typedef struct {
    int16_t input_buffer[MAX_INPUT_SAMPLES];
    int16_t output_buffer[MAX_INPUT_SAMPLES];
    size_t input_length;
    size_t output_length;
    float overlap_buffer[HOP_SIZE];
    complex_t fft_buffer[FFT_SIZE];
    float magnitude[FFT_SIZE / 2];
    float phase[FFT_SIZE / 2];
    float window[FFT_SIZE];
    noise_reduction_state_t noise_state;
    agc_state_t agc_state;
    bool processing_enabled;
} dsp_state_t;

static dsp_state_t dsp;

typedef enum {
    STATE_IDLE,
    STATE_WAITING_LENGTH,
    STATE_RECEIVING_DATA,
    STATE_PROCESSING,
    STATE_SENDING_DATA,
    STATE_CONFIG_WAITING_LENGTH,
    STATE_CONFIG_RECEIVING_DATA,
} comm_state_t;

static volatile comm_state_t current_state = STATE_IDLE;
static volatile size_t bytes_received = 0;
static volatile size_t expected_bytes = 0;
static volatile size_t bytes_sent = 0;

static const struct device *uart_dev;

static void generate_test_signal(void);
static void print_dsp_status(void);
static void print_help(void);
static void print_compression_settings(void);

/* BLE service (ble_service.c) */
extern int ble_service_init(void);
extern bool ble_is_connected(void);
extern void ble_send_response(const uint8_t *data, size_t len);

/*
 * =============================================================================
 * FFT Implementation (Cooley-Tukey Radix-2 DIT)
 * =============================================================================
 */

static uint32_t bit_reverse(uint32_t x, uint32_t log2n)
{
    uint32_t result = 0;
    for (uint32_t i = 0; i < log2n; i++) {
        result = (result << 1) | (x & 1);
        x >>= 1;
    }
    return result;
}

static void fft_forward(complex_t *data, size_t n)
{
    uint32_t log2n = 0;
    size_t temp = n;
    while (temp > 1) {
        temp >>= 1;
        log2n++;
    }

    for (size_t i = 0; i < n; i++) {
        size_t j = bit_reverse(i, log2n);
        if (i < j) {
            complex_t t = data[i];
            data[i] = data[j];
            data[j] = t;
        }
    }

    for (size_t s = 1; s <= log2n; s++) {
        size_t m = 1 << s;
        size_t m2 = m >> 1;
        float theta = -2.0f * M_PI / (float)m;
        complex_t wm = { cosf(theta), sinf(theta) };

        for (size_t k = 0; k < n; k += m) {
            complex_t w = { 1.0f, 0.0f };
            for (size_t j = 0; j < m2; j++) {
                complex_t t;
                t.real = w.real * data[k + j + m2].real - w.imag * data[k + j + m2].imag;
                t.imag = w.real * data[k + j + m2].imag + w.imag * data[k + j + m2].real;
                complex_t u = data[k + j];
                data[k + j].real = u.real + t.real;
                data[k + j].imag = u.imag + t.imag;
                data[k + j + m2].real = u.real - t.real;
                data[k + j + m2].imag = u.imag - t.imag;
                float wr = w.real * wm.real - w.imag * wm.imag;
                float wi = w.real * wm.imag + w.imag * wm.real;
                w.real = wr;
                w.imag = wi;
            }
        }
    }
}

static void fft_inverse(complex_t *data, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        data[i].imag = -data[i].imag;
    }
    
    fft_forward(data, n);
    
    float scale = 1.0f / (float)n;
    for (size_t i = 0; i < n; i++) {
        data[i].real *= scale;
        data[i].imag = -data[i].imag * scale;
    }
}

/*
 * =============================================================================
 * Window Functions
 * =============================================================================
 */

static void init_hann_window(float *window, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        window[i] = 0.5f * (1.0f - cosf(2.0f * M_PI * (float)i / (float)(n - 1)));
    }
}

static void init_sqrt_hann_window(float *window, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        window[i] = sqrtf(0.5f * (1.0f - cosf(2.0f * M_PI * (float)i / (float)(n - 1))));
    }
}

/*
 * =============================================================================
 * Spectral Analysis Utilities
 * =============================================================================
 */

static void compute_magnitude_phase(complex_t *fft_data, float *magnitude, 
                                    float *phase, size_t n)
{
    for (size_t i = 0; i < n / 2; i++) {
        float re = fft_data[i].real;
        float im = fft_data[i].imag;
        magnitude[i] = sqrtf(re * re + im * im);
        phase[i] = atan2f(im, re);
    }
}

static void reconstruct_from_magnitude_phase(complex_t *fft_data, float *magnitude,
                                             float *phase, size_t n)
{
    for (size_t i = 0; i < n / 2; i++) {
        fft_data[i].real = magnitude[i] * cosf(phase[i]);
        fft_data[i].imag = magnitude[i] * sinf(phase[i]);
    }
    for (size_t i = n / 2; i < n; i++) {
        size_t mirror = n - i;
        fft_data[i].real = fft_data[mirror].real;
        fft_data[i].imag = -fft_data[mirror].imag;
    }
}

/*
 * =============================================================================
 * Noise Reduction - Spectral Subtraction with Wiener Filtering
 * =============================================================================
 */

static void estimate_noise_floor(noise_reduction_state_t *state, float *magnitude)
{
    if (state->noise_frames_collected < NOISE_ESTIMATE_FRAMES) {
        for (size_t i = 0; i < FFT_SIZE / 2; i++) {
            state->noise_floor[i] += magnitude[i] / NOISE_ESTIMATE_FRAMES;
        }
        state->noise_frames_collected++;
        
        if (state->noise_frames_collected >= NOISE_ESTIMATE_FRAMES) {
            state->noise_estimated = true;
            LOG_INF("Noise floor estimated from %d frames", NOISE_ESTIMATE_FRAMES);
        }
    }
}

static void update_noise_estimate_adaptive(noise_reduction_state_t *state, 
                                           float *magnitude, float alpha)
{
    if (!state->noise_estimated) return;
    
    for (size_t i = 0; i < FFT_SIZE / 2; i++) {
        if (magnitude[i] < state->noise_floor[i] * 2.0f) {
            state->noise_floor[i] = alpha * state->noise_floor[i] + 
                                    (1.0f - alpha) * magnitude[i];
        }
    }
}

static void apply_spectral_subtraction(noise_reduction_state_t *state,
                                       float *magnitude, size_t n)
{
    if (!state->noise_estimated) return;
    
    const float over_subtraction = 2.0f;
    const float spectral_floor = 0.02f;
    
    for (size_t i = 0; i < n; i++) {
        float noise_estimate = state->noise_floor[i] * over_subtraction;
        float clean_magnitude = magnitude[i] - noise_estimate;
        
        float floor = spectral_floor * magnitude[i];
        if (clean_magnitude < floor) {
            clean_magnitude = floor;
        }
        
        magnitude[i] = clean_magnitude;
    }
}

static void apply_wiener_filter(noise_reduction_state_t *state,
                                float *magnitude, size_t n)
{
    if (!state->noise_estimated) return;
    
    const float noise_overestimate = 1.5f;
    
    for (size_t i = 0; i < n; i++) {
        float signal_power = magnitude[i] * magnitude[i];
        float noise_power = state->noise_floor[i] * state->noise_floor[i] * 
                           noise_overestimate;
        
        float snr = signal_power / (noise_power + 1e-10f);
        float gain = snr / (snr + 1.0f);
        
        gain = fmaxf(gain, 0.1f);
        gain = fminf(gain, 1.0f);
        
        magnitude[i] *= gain;
    }
}

/*
 * =============================================================================
 * Multi-band Wide Dynamic Range Compression (WDRC)
 * =============================================================================
 * Key hearing aid processing: compress loud sounds, amplify soft sounds
 */

static float db_to_linear(float db)
{
    return powf(10.0f, db / 20.0f);
}

static float linear_to_db(float linear)
{
    if (linear < 1e-10f) return -100.0f;
    return 20.0f * log10f(linear);
}

static void apply_runtime_config_to_bands(void)
{
    for (int i = 0; i < NUM_COMPRESSION_BANDS; i++) {
        compression_bands[i].low_bin = default_low_bins[i];
        compression_bands[i].high_bin = default_high_bins[i];
        compression_bands[i].center_freq = channel_center_freqs[i];
        compression_bands[i].threshold_db = runtime_config.channels[i].threshold_db;
        compression_bands[i].ratio = runtime_config.channels[i].ratio;
        compression_bands[i].gain_db = runtime_config.channels[i].gain_db;
        compression_bands[i].mpo_db_spl = runtime_config.channels[i].mpo_db_spl;
        compression_bands[i].envelope = 0.0f;

        float attack_samples = (runtime_config.channels[i].attack_ms / 1000.0f) *
                              SAMPLE_RATE_HZ / HOP_SIZE;
        float release_samples = (runtime_config.channels[i].release_ms / 1000.0f) *
                               SAMPLE_RATE_HZ / HOP_SIZE;

        compression_bands[i].attack_coeff = 1.0f - expf(-1.0f / fmaxf(attack_samples, 0.01f));
        compression_bands[i].release_coeff = 1.0f - expf(-1.0f / fmaxf(release_samples, 0.01f));
    }
}

static void init_compression_bands(void)
{
    apply_runtime_config_to_bands();
}

static float compute_band_energy(float *magnitude, uint16_t low_bin, uint16_t high_bin)
{
    float energy = 0.0f;
    for (uint16_t i = low_bin; i < high_bin && i < FFT_SIZE / 2; i++) {
        energy += magnitude[i] * magnitude[i];
    }
    return sqrtf(energy / (high_bin - low_bin + 1));
}

static float compute_compression_gain(compression_band_t *band, float input_level_db)
{
    if (input_level_db < band->threshold_db) {
        return band->gain_db;
    }
    
    float excess_db = input_level_db - band->threshold_db;
    float compressed_excess = excess_db / band->ratio;
    float output_db = band->threshold_db + compressed_excess;
    float gain_db = output_db - input_level_db + band->gain_db;
    
    return gain_db;
}

static void apply_multiband_compression(float *magnitude)
{
    float master_gain = db_to_linear(runtime_config.global.master_volume_db);

    if (runtime_config.global.mute) {
        for (size_t i = 0; i < FFT_SIZE / 2; i++) {
            magnitude[i] = 0.0f;
        }
        return;
    }

    for (int b = 0; b < NUM_COMPRESSION_BANDS; b++) {
        compression_band_t *band = &compression_bands[b];

        float band_energy = compute_band_energy(magnitude, band->low_bin, band->high_bin);
        float input_level_db = linear_to_db(band_energy);

        if (band_energy > band->envelope) {
            band->envelope += band->attack_coeff * (band_energy - band->envelope);
        } else {
            band->envelope += band->release_coeff * (band_energy - band->envelope);
        }

        float smoothed_level_db = linear_to_db(band->envelope);
        float gain_db = compute_compression_gain(band, smoothed_level_db);
        float gain_linear = db_to_linear(gain_db) * master_gain;

        gain_linear = fminf(gain_linear, 10.0f);
        gain_linear = fmaxf(gain_linear, 0.01f);

        /* MPO (Maximum Power Output) safety limiter per band */
        float mpo_linear = db_to_linear(band->mpo_db_spl - 94.0f); /* ref: 94 dB SPL = 1 Pa */

        for (uint16_t i = band->low_bin; i < band->high_bin && i < FFT_SIZE / 2; i++) {
            float output = magnitude[i] * gain_linear;
            if (output > mpo_linear) {
                output = mpo_linear;
            }
            magnitude[i] = output;
        }
    }
}

/*
 * =============================================================================
 * Automatic Gain Control (AGC)
 * =============================================================================
 */

static void init_agc(agc_state_t *agc)
{
    agc->agc_gain = 1.0f;
    agc->target_level_db = -12.0f;
    agc->max_gain_db = 30.0f;
    agc->min_gain_db = -10.0f;
    
    float attack_time_s = 0.01f;
    float release_time_s = 0.1f;
    float frame_rate = (float)SAMPLE_RATE_HZ / (float)HOP_SIZE;
    
    agc->attack_coeff = 1.0f - expf(-1.0f / (attack_time_s * frame_rate));
    agc->release_coeff = 1.0f - expf(-1.0f / (release_time_s * frame_rate));
}

static float apply_agc(agc_state_t *agc, float *samples, size_t n)
{
    float sum_sq = 0.0f;
    for (size_t i = 0; i < n; i++) {
        sum_sq += samples[i] * samples[i];
    }
    float rms = sqrtf(sum_sq / n);
    float input_level_db = linear_to_db(rms / 32768.0f);
    
    float desired_gain_db = agc->target_level_db - input_level_db;
    desired_gain_db = fminf(desired_gain_db, agc->max_gain_db);
    desired_gain_db = fmaxf(desired_gain_db, agc->min_gain_db);
    float desired_gain = db_to_linear(desired_gain_db);
    
    float coeff = (desired_gain > agc->agc_gain) ? agc->attack_coeff : agc->release_coeff;
    agc->agc_gain += coeff * (desired_gain - agc->agc_gain);
    
    for (size_t i = 0; i < n; i++) {
        samples[i] *= agc->agc_gain;
        
        if (samples[i] > 32000.0f) samples[i] = 32000.0f;
        if (samples[i] < -32000.0f) samples[i] = -32000.0f;
    }
    
    return agc->agc_gain;
}

/*
 * =============================================================================
 * High-Frequency Emphasis (Pre-emphasis)
 * =============================================================================
 * Hearing loss often affects high frequencies more; compensate with emphasis
 */

static void apply_high_frequency_emphasis(float *magnitude, size_t n)
{
    if (!runtime_config.global.hf_emphasis_enabled) return;

    float emphasis_start_freq = runtime_config.global.hf_emphasis_start_freq;
    float max_emphasis_db = runtime_config.global.hf_emphasis_max_db;

    float freq_resolution = (float)SAMPLE_RATE_HZ / (float)FFT_SIZE;
    size_t start_bin = (size_t)(emphasis_start_freq / freq_resolution);

    for (size_t i = start_bin; i < n; i++) {
        float freq = (float)i * freq_resolution;
        float octaves_above_start = log2f(freq / emphasis_start_freq);
        float emphasis_db = octaves_above_start * 3.0f;
        emphasis_db = fminf(emphasis_db, max_emphasis_db);
        float emphasis_gain = db_to_linear(emphasis_db);
        magnitude[i] *= emphasis_gain;
    }
}

/*
 * =============================================================================
 * Noise Gate
 * =============================================================================
 */

static void apply_noise_gate(float *magnitude, size_t n, float threshold_db)
{
    float threshold_linear = db_to_linear(threshold_db);
    
    for (size_t i = 0; i < n; i++) {
        if (magnitude[i] < threshold_linear) {
            magnitude[i] *= 0.1f;
        }
    }
}

/*
 * =============================================================================
 * Complete DSP Processing Pipeline
 * =============================================================================
 */

static void process_frame(int16_t *input, int16_t *output, size_t frame_size)
{
    for (size_t i = 0; i < FFT_SIZE; i++) {
        float sample = (i < frame_size) ? (float)input[i] : 0.0f;
        dsp.fft_buffer[i].real = sample * dsp.window[i];
        dsp.fft_buffer[i].imag = 0.0f;
    }
    
    fft_forward(dsp.fft_buffer, FFT_SIZE);
    compute_magnitude_phase(dsp.fft_buffer, dsp.magnitude, dsp.phase, FFT_SIZE);
    
    if (runtime_config.global.noise_reduction_enabled) {
        if (!dsp.noise_state.noise_estimated) {
            estimate_noise_floor(&dsp.noise_state, dsp.magnitude);
        } else {
            float nr_alpha = 0.90f + 0.09f * (1.0f - runtime_config.global.nr_strength);
            update_noise_estimate_adaptive(&dsp.noise_state, dsp.magnitude, nr_alpha);
            apply_wiener_filter(&dsp.noise_state, dsp.magnitude, FFT_SIZE / 2);
            apply_spectral_subtraction(&dsp.noise_state, dsp.magnitude, FFT_SIZE / 2);
        }
    }
    
    apply_noise_gate(dsp.magnitude, FFT_SIZE / 2, -50.0f);
    apply_multiband_compression(dsp.magnitude);
    apply_high_frequency_emphasis(dsp.magnitude, FFT_SIZE / 2);
    
    reconstruct_from_magnitude_phase(dsp.fft_buffer, dsp.magnitude, dsp.phase, FFT_SIZE);
    fft_inverse(dsp.fft_buffer, FFT_SIZE);
    
    for (size_t i = 0; i < HOP_SIZE; i++) {
        float sample = dsp.fft_buffer[i].real * dsp.window[i] + dsp.overlap_buffer[i];
        output[i] = (int16_t)fminf(fmaxf(sample, -32768.0f), 32767.0f);
    }
    
    for (size_t i = 0; i < HOP_SIZE; i++) {
        dsp.overlap_buffer[i] = dsp.fft_buffer[i + HOP_SIZE].real * dsp.window[i + HOP_SIZE];
    }
}

static void process_audio_buffer(void)
{
    LOG_INF("Processing %d samples through hearing aid DSP pipeline...", dsp.input_length);
    
    dsp.noise_state.noise_frames_collected = 0;
    dsp.noise_state.noise_estimated = false;
    memset(dsp.noise_state.noise_floor, 0, sizeof(dsp.noise_state.noise_floor));
    memset(dsp.overlap_buffer, 0, sizeof(dsp.overlap_buffer));
    init_compression_bands();
    init_agc(&dsp.agc_state);
    
    size_t num_frames = (dsp.input_length > HOP_SIZE) ? 
                        (dsp.input_length - HOP_SIZE) / HOP_SIZE : 0;
    
    if (num_frames < NOISE_ESTIMATE_FRAMES + 1) {
        LOG_WRN("Input too short for proper noise estimation, using minimal processing");
        for (size_t i = 0; i < dsp.input_length; i++) {
            dsp.output_buffer[i] = dsp.input_buffer[i];
        }
        dsp.output_length = dsp.input_length;
        return;
    }
    
    dsp.output_length = 0;
    
    for (size_t frame = 0; frame < num_frames; frame++) {
        size_t input_offset = frame * HOP_SIZE;
        size_t output_offset = frame * HOP_SIZE;
        
        process_frame(&dsp.input_buffer[input_offset], 
                     &dsp.output_buffer[output_offset], 
                     HOP_SIZE);
        
        dsp.output_length = output_offset + HOP_SIZE;
    }
    
    float output_samples[HOP_SIZE];
    for (size_t i = 0; i < dsp.output_length && i < MAX_INPUT_SAMPLES; i++) {
        output_samples[i % HOP_SIZE] = (float)dsp.output_buffer[i];
        
        if ((i + 1) % HOP_SIZE == 0 || i == dsp.output_length - 1) {
            size_t chunk_size = (i % HOP_SIZE) + 1;
            apply_agc(&dsp.agc_state, output_samples, chunk_size);
            
            size_t start = i - (i % HOP_SIZE);
            for (size_t j = 0; j < chunk_size; j++) {
                dsp.output_buffer[start + j] = (int16_t)output_samples[j];
            }
        }
    }
    
    LOG_INF("Processing complete. Output: %d samples", dsp.output_length);
}

/*
 * =============================================================================
 * DSP State Initialization
 * =============================================================================
 */

static void init_dsp_state(void)
{
    memset(&dsp, 0, sizeof(dsp));

    init_default_runtime_config();
    init_sqrt_hann_window(dsp.window, FFT_SIZE);
    init_compression_bands();
    init_agc(&dsp.agc_state);

    dsp.processing_enabled = true;

    LOG_INF("DSP state initialized");
    LOG_INF("  Firmware: v%d.%d.%d", FIRMWARE_VERSION_MAJOR, FIRMWARE_VERSION_MINOR, FIRMWARE_VERSION_PATCH);
    LOG_INF("  FFT Size: %d", FFT_SIZE);
    LOG_INF("  Hop Size: %d", HOP_SIZE);
    LOG_INF("  Sample Rate: %d Hz", SAMPLE_RATE_HZ);
    LOG_INF("  Compression Bands: %d", NUM_COMPRESSION_BANDS);
    LOG_INF("  Runtime config: ENABLED (UART + BLE)");
}

/*
 * =============================================================================
 * UART Communication
 * =============================================================================
 */

/*
 * =============================================================================
 * Configuration Protocol Handler (shared by UART and BLE)
 * =============================================================================
 */

static void send_response(const uint8_t *data, size_t len);

static uint8_t compute_checksum(const uint8_t *data, size_t len)
{
    uint8_t checksum = 0;
    for (size_t i = 0; i < len; i++) {
        checksum ^= data[i];
    }
    return checksum;
}

static void send_ack(uint8_t cmd)
{
    uint8_t resp[4] = { CMD_ACK, 1, 0, cmd };
    send_response(resp, 4);
}

static void send_nack(uint8_t cmd, uint8_t error_code)
{
    uint8_t resp[5] = { CMD_NACK, 2, 0, cmd, error_code };
    send_response(resp, 5);
}

void handle_config_command(uint8_t cmd, uint8_t *payload, uint16_t len)
{
    switch (cmd) {
    case CMD_WRITE_FULL_CONFIG: {
        /* Expect 12 x channel_config_wire_t = 288 bytes + 1 checksum */
        uint16_t expected = sizeof(channel_config_wire_t) * NUM_COMPRESSION_BANDS;
        if (len < expected + 1) {
            LOG_ERR("W: payload too short (%d, need %d+1)", len, expected);
            send_nack(cmd, 1);
            return;
        }
        uint8_t rx_checksum = payload[expected];
        uint8_t calc_checksum = compute_checksum(payload, expected);
        if (rx_checksum != calc_checksum) {
            LOG_ERR("W: checksum mismatch (rx=0x%02x calc=0x%02x)", rx_checksum, calc_checksum);
            send_nack(cmd, 2);
            return;
        }
        memcpy(runtime_config.channels, payload, expected);
        apply_runtime_config_to_bands();
        LOG_INF("Full config updated (%d channels)", NUM_COMPRESSION_BANDS);
        send_ack(cmd);
        break;
    }

    case CMD_WRITE_SINGLE_CHAN: {
        /* Expect 1 byte index + channel_config_wire_t + 1 checksum */
        uint16_t expected = 1 + sizeof(channel_config_wire_t);
        if (len < expected + 1) {
            send_nack(cmd, 1);
            return;
        }
        uint8_t idx = payload[0];
        if (idx >= NUM_COMPRESSION_BANDS) {
            send_nack(cmd, 3);
            return;
        }
        uint8_t rx_checksum = payload[expected];
        uint8_t calc_checksum = compute_checksum(payload, expected);
        if (rx_checksum != calc_checksum) {
            send_nack(cmd, 2);
            return;
        }
        memcpy(&runtime_config.channels[idx], &payload[1], sizeof(channel_config_wire_t));
        apply_runtime_config_to_bands();
        LOG_INF("Channel %d config updated", idx);
        send_ack(cmd);
        break;
    }

    case CMD_WRITE_GLOBAL: {
        uint16_t expected = sizeof(global_config_wire_t);
        if (len < expected + 1) {
            send_nack(cmd, 1);
            return;
        }
        uint8_t rx_checksum = payload[expected];
        uint8_t calc_checksum = compute_checksum(payload, expected);
        if (rx_checksum != calc_checksum) {
            send_nack(cmd, 2);
            return;
        }
        memcpy(&runtime_config.global, payload, expected);
        LOG_INF("Global config updated (vol=%.1f dB, mute=%d, NR=%d)",
                (double)runtime_config.global.master_volume_db,
                runtime_config.global.mute,
                runtime_config.global.noise_reduction_enabled);
        send_ack(cmd);
        break;
    }

    case CMD_READ_CONFIG: {
        /* Send 'r' + length + all channels + global + checksum */
        uint16_t chan_size = sizeof(channel_config_wire_t) * NUM_COMPRESSION_BANDS;
        uint16_t glob_size = sizeof(global_config_wire_t);
        uint16_t payload_size = chan_size + glob_size;
        uint8_t resp[4 + sizeof(channel_config_wire_t) * NUM_COMPRESSION_BANDS +
                     sizeof(global_config_wire_t) + 1];

        resp[0] = CMD_READ_CONFIG_RESP;
        resp[1] = (payload_size + 1) & 0xFF;
        resp[2] = ((payload_size + 1) >> 8) & 0xFF;
        memcpy(&resp[3], runtime_config.channels, chan_size);
        memcpy(&resp[3 + chan_size], &runtime_config.global, glob_size);
        resp[3 + payload_size] = compute_checksum(&resp[3], payload_size);

        send_response(resp, 3 + payload_size + 1);
        LOG_INF("Config readback sent (%d bytes)", payload_size);
        break;
    }

    case CMD_READ_STATUS: {
        status_wire_t status = {
            .firmware_major = FIRMWARE_VERSION_MAJOR,
            .firmware_minor = FIRMWARE_VERSION_MINOR,
            .firmware_patch = FIRMWARE_VERSION_PATCH,
            .num_channels = NUM_COMPRESSION_BANDS,
            .sample_rate = SAMPLE_RATE_HZ,
            .fft_size = FFT_SIZE,
            .agc_gain_db = linear_to_db(dsp.agc_state.agc_gain),
            .noise_estimated = dsp.noise_state.noise_estimated ? 1 : 0,
            .processing_enabled = dsp.processing_enabled ? 1 : 0,
        };

        uint16_t payload_size = sizeof(status_wire_t);
        uint8_t resp[3 + sizeof(status_wire_t) + 1];
        resp[0] = CMD_READ_STATUS_RESP;
        resp[1] = (payload_size + 1) & 0xFF;
        resp[2] = ((payload_size + 1) >> 8) & 0xFF;
        memcpy(&resp[3], &status, payload_size);
        resp[3 + payload_size] = compute_checksum(&resp[3], payload_size);

        send_response(resp, 3 + payload_size + 1);
        LOG_INF("Status sent");
        break;
    }

    default:
        LOG_WRN("Unknown config command: 0x%02x", cmd);
        send_nack(cmd, 0xFF);
        break;
    }
}

/*
 * =============================================================================
 * UART Communication
 * =============================================================================
 */

static void send_response(const uint8_t *data, size_t len)
{
    /* Send via UART */
    for (size_t i = 0; i < len; i++) {
        uart_poll_out(uart_dev, data[i]);
    }

    /* Also send via BLE if connected */
    if (ble_is_connected()) {
        ble_send_response(data, len);
    }
}

static void send_processed_data(void)
{
    if (dsp.output_length == 0) {
        LOG_WRN("No output data to send");
        return;
    }
    
    LOG_INF("Sending %d processed samples via UART...", dsp.output_length);
    
    size_t total_bytes = dsp.output_length * 2;
    uint8_t len_low = total_bytes & 0xFF;
    uint8_t len_high = (total_bytes >> 8) & 0xFF;
    
    uart_poll_out(uart_dev, 'R');
    uart_poll_out(uart_dev, len_low);
    uart_poll_out(uart_dev, len_high);
    
    for (size_t i = 0; i < dsp.output_length; i++) {
        int16_t sample = dsp.output_buffer[i];
        uart_poll_out(uart_dev, sample & 0xFF);
        uart_poll_out(uart_dev, (sample >> 8) & 0xFF);
    }
    
    LOG_INF("Transmission complete: %d bytes sent", total_bytes + 3);
}

static void uart_rx_callback(const struct device *dev, void *user_data)
{
    uint8_t c;
    
    if (!uart_irq_update(dev)) {
        return;
    }

    while (uart_irq_rx_ready(dev)) {
        uart_fifo_read(dev, &c, 1);
        
        switch (current_state) {
            case STATE_WAITING_LENGTH:
                if (bytes_received == 0) {
                    expected_bytes = c;
                    bytes_received = 1;
                } else {
                    expected_bytes |= ((size_t)c << 8);
                    bytes_received = 0;
                    
                    if (expected_bytes > MAX_INPUT_SAMPLES * 2) {
                        LOG_ERR("Input too large: %d bytes (max %d)", 
                               expected_bytes, MAX_INPUT_SAMPLES * 2);
                        current_state = STATE_IDLE;
                    } else if (expected_bytes < FFT_SIZE * 2) {
                        LOG_WRN("Input very short (%d bytes), processing may be limited", 
                               expected_bytes);
                        dsp.input_length = expected_bytes / 2;
                        current_state = STATE_RECEIVING_DATA;
                    } else {
                        LOG_INF("Expecting %d bytes (%d samples)", 
                               expected_bytes, expected_bytes / 2);
                        dsp.input_length = expected_bytes / 2;
                        current_state = STATE_RECEIVING_DATA;
                    }
                }
                break;

            case STATE_RECEIVING_DATA:
                {
                    size_t sample_idx = bytes_received / 2;
                    size_t byte_pos = bytes_received % 2;
                    
                    if (sample_idx < MAX_INPUT_SAMPLES) {
                        if (byte_pos == 0) {
                            dsp.input_buffer[sample_idx] = c;
                        } else {
                            dsp.input_buffer[sample_idx] |= ((int16_t)c << 8);
                        }
                    }
                    
                    bytes_received++;
                    
                    if (bytes_received >= expected_bytes) {
                        LOG_INF("Received %d samples", dsp.input_length);
                        current_state = STATE_PROCESSING;
                        bytes_received = 0;
                    }
                }
                break;

            case STATE_CONFIG_WAITING_LENGTH:
                if (config_rx_pos == 0) {
                    config_rx_expected = c;
                    config_rx_pos = 1;
                } else {
                    config_rx_expected |= ((size_t)c << 8);
                    config_rx_pos = 0;
                    if (config_rx_expected > CONFIG_BUFFER_SIZE) {
                        LOG_ERR("Config payload too large: %d", config_rx_expected);
                        current_state = STATE_IDLE;
                    } else if (config_rx_expected == 0) {
                        /* Empty payload commands (R, S) */
                        handle_config_command(config_rx_cmd, NULL, 0);
                        current_state = STATE_IDLE;
                    } else {
                        current_state = STATE_CONFIG_RECEIVING_DATA;
                    }
                }
                break;

            case STATE_CONFIG_RECEIVING_DATA:
                config_rx_buffer[config_rx_pos++] = c;
                if (config_rx_pos >= config_rx_expected) {
                    handle_config_command(config_rx_cmd, config_rx_buffer,
                                          config_rx_expected);
                    config_rx_pos = 0;
                    current_state = STATE_IDLE;
                }
                break;

            default:
                if (c == CMD_PROCESS_AUDIO) {
                    LOG_INF("Process command received - waiting for data length...");
                    current_state = STATE_WAITING_LENGTH;
                    bytes_received = 0;
                    expected_bytes = 0;
                }
                else if (c == 'T') {
                    LOG_INF("Test mode - generating noisy test signal...");
                    generate_test_signal();
                    current_state = STATE_PROCESSING;
                }
                else if (c == CMD_WRITE_FULL_CONFIG || c == CMD_WRITE_SINGLE_CHAN ||
                         c == CMD_WRITE_GLOBAL) {
                    config_rx_cmd = c;
                    config_rx_pos = 0;
                    config_rx_expected = 0;
                    current_state = STATE_CONFIG_WAITING_LENGTH;
                }
                else if (c == CMD_READ_CONFIG || c == CMD_READ_STATUS) {
                    /* These commands have length field (0) but we handle immediately */
                    config_rx_cmd = c;
                    config_rx_pos = 0;
                    config_rx_expected = 0;
                    current_state = STATE_CONFIG_WAITING_LENGTH;
                }
                else if (c == 'H' || c == '?') {
                    print_help();
                }
                else if (c == 'C') {
                    print_compression_settings();
                }
                break;
        }
    }
}

/*
 * =============================================================================
 * Test Signal Generation
 * =============================================================================
 */

static void generate_test_signal(void)
{
    LOG_INF("Generating test signal: speech-like + noise...");
    
    const float speech_freqs[] = { 300.0f, 500.0f, 1000.0f, 2000.0f, 3000.0f };
    const float speech_amps[] = { 0.3f, 0.5f, 0.4f, 0.2f, 0.1f };
    const int num_freqs = 5;
    
    dsp.input_length = 1024;
    
    for (size_t i = 0; i < dsp.input_length; i++) {
        float t = (float)i / (float)SAMPLE_RATE_HZ;
        float sample = 0.0f;
        
        float envelope = sinf(M_PI * (float)i / (float)dsp.input_length);
        envelope = envelope * envelope;
        
        for (int f = 0; f < num_freqs; f++) {
            float freq_variation = 1.0f + 0.02f * sinf(2.0f * M_PI * 3.0f * t);
            sample += speech_amps[f] * sinf(2.0f * M_PI * speech_freqs[f] * 
                                            freq_variation * t);
        }
        sample *= envelope;
        
        float noise = ((float)(rand() % 2000) / 1000.0f - 1.0f) * 0.4f;
        float hf_noise = ((float)(rand() % 2000) / 1000.0f - 1.0f) * 0.2f;
        
        static float hf_filter = 0.0f;
        hf_filter = 0.9f * hf_filter + 0.1f * hf_noise;
        
        sample += noise + hf_filter;
        
        dsp.input_buffer[i] = (int16_t)(sample * 8000.0f);
    }
    
    LOG_INF("Test signal generated: %d samples", dsp.input_length);
    LOG_INF("Contains: 300/500/1000/2000/3000 Hz speech simulation + broadband noise");
}

/*
 * =============================================================================
 * Status and Help Functions
 * =============================================================================
 */

static void print_dsp_status(void)
{
    printk("\n");
    printk("╔══════════════════════════════════════════════════════════════════╗\n");
    printk("║           HEARING AID DSP - STATUS                               ║\n");
    printk("╠══════════════════════════════════════════════════════════════════╣\n");
    printk("║  Sample Rate:        %5d Hz                                    ║\n", SAMPLE_RATE_HZ);
    printk("║  FFT Size:           %5d samples                               ║\n", FFT_SIZE);
    printk("║  Hop Size:           %5d samples                               ║\n", HOP_SIZE);
    printk("║  Compression Bands:  %5d                                       ║\n", NUM_COMPRESSION_BANDS);
    printk("║  Input Buffer:       %5d samples                               ║\n", dsp.input_length);
    printk("║  Output Buffer:      %5d samples                               ║\n", dsp.output_length);
    printk("║  Noise Estimated:    %s                                        ║\n", 
           dsp.noise_state.noise_estimated ? "YES" : "NO ");
    printk("║  AGC Gain:           %5.2f dB                                   ║\n", 
           linear_to_db(dsp.agc_state.agc_gain));
    printk("╚══════════════════════════════════════════════════════════════════╝\n");
    printk("\n");
}

static void print_compression_settings(void)
{
    printk("\n");
    printk("╔══════════════════════════════════════════════════════════════════╗\n");
    printk("║           COMPRESSION BAND SETTINGS                              ║\n");
    printk("╠══════════════════════════════════════════════════════════════════╣\n");
    printk("║  Band   Freq(Hz)   Threshold   Ratio    Gain    MPO               ║\n");
    printk("║  ────   ────────   ─────────   ─────   ──────  ─────             ║\n");
    
    for (int i = 0; i < NUM_COMPRESSION_BANDS; i++) {
        printk("║  %4d   %7.0f   %6.1f dB   %4.1f:1   %+5.1f dB   %5.0f MPO     ║\n",
               i,
               compression_bands[i].center_freq,
               compression_bands[i].threshold_db,
               compression_bands[i].ratio,
               compression_bands[i].gain_db,
               compression_bands[i].mpo_db_spl);
    }
    
    printk("╚══════════════════════════════════════════════════════════════════╝\n");
    printk("\n");
}

static void print_help(void)
{
    printk("\n");
    printk("╔══════════════════════════════════════════════════════════════════╗\n");
    printk("║     HEARING AID DSP PROCESSOR - nRF54L15                         ║\n");
    printk("║                 Cochlear Implant Project                         ║\n");
    printk("╠══════════════════════════════════════════════════════════════════╣\n");
    printk("║                                                                  ║\n");
    printk("║  COMMANDS:                                                       ║\n");
    printk("║    P - Process audio (send 'P' + 2B len + samples)               ║\n");
    printk("║    T - Generate and process test signal                          ║\n");
    printk("║    W - Write full config (12 ch x 24B + checksum)                ║\n");
    printk("║    w - Write single channel (1B idx + 24B + checksum)            ║\n");
    printk("║    G - Write global config (20B + checksum)                      ║\n");
    printk("║    R - Read current config (returns 'r' + config)                ║\n");
    printk("║    S - Read status (returns 's' + status)                        ║\n");
    printk("║    C - Print compression band settings                           ║\n");
    printk("║    H - Show this help message                                    ║\n");
    printk("║                                                                  ║\n");
    printk("║  PROTOCOL: [cmd:1][len:2 LE][payload:N][checksum:1 XOR]          ║\n");
    printk("║  AUDIO:    'P' + len_low + len_high + samples (16-bit LE)        ║\n");
    printk("║  ACK/NACK: 'A'/'N' + len + echoed_cmd [+ error_code]            ║\n");
    printk("║                                                                  ║\n");
    printk("║  DSP PIPELINE (%d-band WDRC):                                   ║\n", NUM_COMPRESSION_BANDS);
    printk("║    1. FFT-based spectral analysis (256-pt)                       ║\n");
    printk("║    2. Noise estimation (first %d frames)                         ║\n", NOISE_ESTIMATE_FRAMES);
    printk("║    3. Wiener filtering + spectral subtraction                    ║\n");
    printk("║    4. Noise gate                                                 ║\n");
    printk("║    5. %d-band WDRC with per-band MPO                            ║\n", NUM_COMPRESSION_BANDS);
    printk("║    6. Configurable high-frequency emphasis                       ║\n");
    printk("║    7. Inverse FFT + overlap-add synthesis                        ║\n");
    printk("║    8. Automatic Gain Control (AGC)                               ║\n");
    printk("║                                                                  ║\n");
    printk("╚══════════════════════════════════════════════════════════════════╝\n");
    printk("\n");
}

/*
 * =============================================================================
 * UART Initialization
 * =============================================================================
 */

static int uart_init(void)
{
    uart_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));
    
    if (!device_is_ready(uart_dev)) {
        LOG_ERR("UART device not ready");
        return -ENODEV;
    }

    uart_irq_callback_set(uart_dev, uart_rx_callback);
    uart_irq_rx_enable(uart_dev);

    LOG_INF("UART initialized at 115200 baud");
    return 0;
}

/*
 * =============================================================================
 * Main Application
 * =============================================================================
 */

int main(void)
{
    int ret;

    srand(k_uptime_get_32());

    LOG_INF("═══════════════════════════════════════════════════════════════");
    LOG_INF("  Hearing Aid DSP Processor - Cochlear Implant Project");
    LOG_INF("  Target: nRF54L15-DK");
    LOG_INF("═══════════════════════════════════════════════════════════════");

    k_sleep(K_MSEC(100));

    init_dsp_state();

    ret = uart_init();
    if (ret < 0) {
        LOG_ERR("UART initialization failed!");
        return ret;
    }

    ret = ble_service_init();
    if (ret < 0) {
        LOG_WRN("BLE initialization failed (err %d) - continuing with UART only", ret);
    }

    print_help();

    LOG_INF("System ready. UART and BLE active. Send 'P' for audio, 'W'/'R'/'S' for config.");

    while (1) {
        if (current_state == STATE_PROCESSING) {
            current_state = STATE_IDLE;
            
            if (dsp.input_length > 0) {
                process_audio_buffer();
                send_processed_data();
                
                print_dsp_status();
            }
        }

        k_sleep(K_MSEC(10));
    }

    return 0;
}
