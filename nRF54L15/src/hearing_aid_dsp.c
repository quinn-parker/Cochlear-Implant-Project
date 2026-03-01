/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cochlear Implant Project - Hearing Aid DSP Signal Processor
 * Target: nRF54L15
 *
 * Advanced DSP processing pipeline mimicking hearing aid signal processing:
 * - Spectral noise reduction (Wiener filtering / spectral subtraction)
 * - Multi-band dynamic range compression (WDRC)
 * - Automatic Gain Control (AGC)
 * - High-frequency emphasis
 * - Feedback cancellation preparation
 *
 * Serial Protocol:
 * Input:  'P' + 2-byte length (LE) + 16-bit samples (LE)
 * Output: 2-byte length (LE) + processed 16-bit samples (LE)
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
#define NUM_COMPRESSION_BANDS   8
#define MAX_INPUT_SAMPLES       2048
#define NOISE_ESTIMATE_FRAMES   10

#ifndef M_PI
#define M_PI 3.14159265358979323846f
#endif

/*
 * =============================================================================
 * Compression Band Configuration (Audiogram-based)
 * =============================================================================
 * Typical hearing aid uses logarithmic frequency bands
 * These bands cover speech-critical frequencies
 */

typedef struct {
    uint16_t low_bin;
    uint16_t high_bin;
    float center_freq;
    float threshold_db;
    float ratio;
    float attack_ms;
    float release_ms;
    float gain_db;
    float envelope;
} compression_band_t;

static compression_band_t compression_bands[NUM_COMPRESSION_BANDS] = {
    { 0,   2,   125.0f,  -40.0f, 1.5f, 5.0f,  50.0f,  6.0f, 0.0f },
    { 2,   4,   250.0f,  -40.0f, 1.8f, 5.0f,  50.0f,  3.0f, 0.0f },
    { 4,   8,   500.0f,  -35.0f, 2.0f, 5.0f,  50.0f,  0.0f, 0.0f },
    { 8,  16,  1000.0f,  -35.0f, 2.5f, 5.0f,  50.0f,  0.0f, 0.0f },
    {16,  32,  2000.0f,  -30.0f, 3.0f, 5.0f,  50.0f,  3.0f, 0.0f },
    {32,  48,  3000.0f,  -30.0f, 3.0f, 5.0f,  50.0f,  6.0f, 0.0f },
    {48,  80,  5000.0f,  -30.0f, 2.5f, 5.0f,  50.0f,  6.0f, 0.0f },
    {80, 128,  7000.0f,  -35.0f, 2.0f, 5.0f,  50.0f,  3.0f, 0.0f },
};

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
    STATE_SENDING_DATA
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

static void init_compression_bands(void)
{
    float freq_resolution = (float)SAMPLE_RATE_HZ / (float)FFT_SIZE;
    
    for (int i = 0; i < NUM_COMPRESSION_BANDS; i++) {
        compression_bands[i].envelope = 0.0f;
        
        float attack_samples = (compression_bands[i].attack_ms / 1000.0f) * 
                              SAMPLE_RATE_HZ / HOP_SIZE;
        float release_samples = (compression_bands[i].release_ms / 1000.0f) * 
                               SAMPLE_RATE_HZ / HOP_SIZE;
        
        compression_bands[i].attack_ms = 1.0f - expf(-1.0f / attack_samples);
        compression_bands[i].release_ms = 1.0f - expf(-1.0f / release_samples);
    }
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
    for (int b = 0; b < NUM_COMPRESSION_BANDS; b++) {
        compression_band_t *band = &compression_bands[b];
        
        float band_energy = compute_band_energy(magnitude, band->low_bin, band->high_bin);
        float input_level_db = linear_to_db(band_energy);
        
        float target_envelope;
        if (band_energy > band->envelope) {
            target_envelope = band_energy;
            band->envelope += band->attack_ms * (target_envelope - band->envelope);
        } else {
            target_envelope = band_energy;
            band->envelope += band->release_ms * (target_envelope - band->envelope);
        }
        
        float smoothed_level_db = linear_to_db(band->envelope);
        float gain_db = compute_compression_gain(band, smoothed_level_db);
        float gain_linear = db_to_linear(gain_db);
        
        gain_linear = fminf(gain_linear, 10.0f);
        gain_linear = fmaxf(gain_linear, 0.01f);
        
        for (uint16_t i = band->low_bin; i < band->high_bin && i < FFT_SIZE / 2; i++) {
            magnitude[i] *= gain_linear;
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
    const float emphasis_start_freq = 1500.0f;
    const float max_emphasis_db = 12.0f;
    
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
    
    if (!dsp.noise_state.noise_estimated) {
        estimate_noise_floor(&dsp.noise_state, dsp.magnitude);
    } else {
        update_noise_estimate_adaptive(&dsp.noise_state, dsp.magnitude, 0.98f);
        apply_wiener_filter(&dsp.noise_state, dsp.magnitude, FFT_SIZE / 2);
        apply_spectral_subtraction(&dsp.noise_state, dsp.magnitude, FFT_SIZE / 2);
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
    
    init_sqrt_hann_window(dsp.window, FFT_SIZE);
    init_compression_bands();
    init_agc(&dsp.agc_state);
    
    dsp.processing_enabled = true;
    
    LOG_INF("DSP state initialized");
    LOG_INF("  FFT Size: %d", FFT_SIZE);
    LOG_INF("  Hop Size: %d", HOP_SIZE);
    LOG_INF("  Sample Rate: %d Hz", SAMPLE_RATE_HZ);
    LOG_INF("  Compression Bands: %d", NUM_COMPRESSION_BANDS);
}

/*
 * =============================================================================
 * UART Communication
 * =============================================================================
 */

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

            default:
                if (c == 'P') {
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
                else if (c == 'S') {
                    print_dsp_status();
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
    printk("║  Band   Freq(Hz)   Threshold   Ratio   Gain                      ║\n");
    printk("║  ────   ────────   ─────────   ─────   ────                      ║\n");
    
    for (int i = 0; i < NUM_COMPRESSION_BANDS; i++) {
        printk("║  %4d   %7.0f   %6.1f dB   %4.1f:1   %+4.1f dB                   ║\n",
               i + 1,
               compression_bands[i].center_freq,
               compression_bands[i].threshold_db,
               compression_bands[i].ratio,
               compression_bands[i].gain_db);
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
    printk("║    P - Process audio (send 'P' + 2-byte length + samples)        ║\n");
    printk("║    T - Generate and process test signal                          ║\n");
    printk("║    S - Show DSP status                                           ║\n");
    printk("║    C - Show compression band settings                            ║\n");
    printk("║    H - Show this help message                                    ║\n");
    printk("║                                                                  ║\n");
    printk("║  SERIAL PROTOCOL:                                                ║\n");
    printk("║    Input:  'P' + len_low + len_high + samples (16-bit LE)        ║\n");
    printk("║    Output: 'R' + len_low + len_high + samples (16-bit LE)        ║\n");
    printk("║                                                                  ║\n");
    printk("║  DSP PIPELINE:                                                   ║\n");
    printk("║    1. FFT-based spectral analysis                                ║\n");
    printk("║    2. Noise estimation (first %d frames)                         ║\n", NOISE_ESTIMATE_FRAMES);
    printk("║    3. Wiener filtering + spectral subtraction                    ║\n");
    printk("║    4. Noise gate                                                 ║\n");
    printk("║    5. %d-band dynamic range compression (WDRC)                   ║\n", NUM_COMPRESSION_BANDS);
    printk("║    6. High-frequency emphasis                                    ║\n");
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

    print_help();

    LOG_INF("System ready. Send 'P' + data to process, or 'T' for test mode.");

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
