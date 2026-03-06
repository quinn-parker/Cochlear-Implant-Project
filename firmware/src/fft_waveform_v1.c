/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cochlear Implant Project - FFT Waveform Analyzer v1.0
 * Target: nRF54L15
 *
 * This program stores a waveform (song with noise), performs FFT analysis,
 * and displays the frequency spectrum on the console via nRF54L15 dev link.
 *
 * Features:
 * - Waveform upload via UART (or use built-in test waveform)
 * - Real-time FFT computation using Cooley-Tukey algorithm
 * - ASCII spectrum display on console
 * - Frequency bin analysis and magnitude calculation
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/sys/printk.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

LOG_MODULE_REGISTER(fft_analyzer, LOG_LEVEL_INF);

/*
 * =============================================================================
 * FFT Configuration
 * =============================================================================
 */

#define FFT_SIZE            256     /* FFT size (must be power of 2) */
#define SAMPLE_RATE_HZ      16000   /* Sample rate for frequency calculation */
#define MAX_WAVEFORM_SIZE   1024    /* Maximum waveform storage size */
#define SPECTRUM_WIDTH      64      /* ASCII spectrum display width */
#define SPECTRUM_HEIGHT     20      /* ASCII spectrum display height */

/* Pi constant for FFT calculations */
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/*
 * =============================================================================
 * Data Structures
 * =============================================================================
 */

/* Complex number structure for FFT */
typedef struct {
    float real;
    float imag;
} complex_t;

/* Waveform storage */
static int16_t waveform_buffer[MAX_WAVEFORM_SIZE];
static size_t waveform_length = 0;

/* FFT buffers */
static complex_t fft_input[FFT_SIZE];
static complex_t fft_output[FFT_SIZE];
static float magnitude_spectrum[FFT_SIZE / 2];

/* UART device for waveform upload */
static const struct device *uart_dev;

/* State machine for upload */
typedef enum {
    STATE_IDLE,
    STATE_WAITING_LENGTH,
    STATE_RECEIVING_DATA,
    STATE_PROCESSING
} upload_state_t;

static volatile upload_state_t current_state = STATE_IDLE;
static volatile size_t bytes_received = 0;
static volatile size_t expected_bytes = 0;

/*
 * =============================================================================
 * FFT Implementation - Cooley-Tukey Radix-2 DIT Algorithm
 * =============================================================================
 */

/**
 * Bit-reverse an index for FFT reordering
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

/**
 * Compute FFT using Cooley-Tukey Radix-2 DIT algorithm
 * Input: complex array of size N (must be power of 2)
 * Output: complex array of size N containing frequency domain data
 */
static void fft_compute(complex_t *data, size_t n)
{
    /* Calculate log2(n) */
    uint32_t log2n = 0;
    size_t temp = n;
    while (temp > 1) {
        temp >>= 1;
        log2n++;
    }

    /* Bit-reversal permutation */
    for (size_t i = 0; i < n; i++) {
        size_t j = bit_reverse(i, log2n);
        if (i < j) {
            /* Swap data[i] and data[j] */
            complex_t t = data[i];
            data[i] = data[j];
            data[j] = t;
        }
    }

    /* Cooley-Tukey iterative FFT */
    for (size_t s = 1; s <= log2n; s++) {
        size_t m = 1 << s;                          /* 2^s */
        size_t m2 = m >> 1;                         /* m/2 */
        
        /* Principal root of unity */
        float theta = -2.0f * M_PI / (float)m;
        complex_t wm = { cosf(theta), sinf(theta) };

        for (size_t k = 0; k < n; k += m) {
            complex_t w = { 1.0f, 0.0f };           /* Current twiddle factor */
            
            for (size_t j = 0; j < m2; j++) {
                /* Butterfly operation */
                complex_t t;
                t.real = w.real * data[k + j + m2].real - w.imag * data[k + j + m2].imag;
                t.imag = w.real * data[k + j + m2].imag + w.imag * data[k + j + m2].real;
                
                complex_t u = data[k + j];
                
                data[k + j].real = u.real + t.real;
                data[k + j].imag = u.imag + t.imag;
                
                data[k + j + m2].real = u.real - t.real;
                data[k + j + m2].imag = u.imag - t.imag;
                
                /* Update twiddle factor: w = w * wm */
                float wr = w.real * wm.real - w.imag * wm.imag;
                float wi = w.real * wm.imag + w.imag * wm.real;
                w.real = wr;
                w.imag = wi;
            }
        }
    }
}

/**
 * Calculate magnitude spectrum from complex FFT output
 */
static void calculate_magnitude_spectrum(complex_t *fft_data, float *magnitudes, size_t n)
{
    /* Only compute first half (positive frequencies) due to symmetry */
    for (size_t i = 0; i < n / 2; i++) {
        float real = fft_data[i].real;
        float imag = fft_data[i].imag;
        magnitudes[i] = sqrtf(real * real + imag * imag);
    }
}

/**
 * Apply Hanning window to reduce spectral leakage
 */
static void apply_hanning_window(int16_t *input, complex_t *output, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        /* Hanning window: w[n] = 0.5 * (1 - cos(2*pi*n/(N-1))) */
        float window = 0.5f * (1.0f - cosf(2.0f * M_PI * (float)i / (float)(n - 1)));
        output[i].real = (float)input[i] * window;
        output[i].imag = 0.0f;
    }
}

/*
 * =============================================================================
 * Test Waveform Generation - Song with Noise
 * =============================================================================
 */

/**
 * Generate a test waveform simulating a song with noise
 * Contains multiple frequency components plus random noise
 */
static void generate_test_waveform(void)
{
    LOG_INF("Generating test waveform (song with noise)...");

    /* Musical frequencies (Hz) - simulating a chord */
    const float frequencies[] = {
        261.63f,    /* C4 - Middle C */
        329.63f,    /* E4 */
        392.00f,    /* G4 */
        523.25f,    /* C5 - Octave */
        1000.0f,    /* 1 kHz test tone */
        2000.0f,    /* 2 kHz harmonic */
    };
    const int num_freqs = sizeof(frequencies) / sizeof(frequencies[0]);

    /* Amplitudes for each frequency (relative) */
    const float amplitudes[] = {
        1.0f,       /* Fundamental */
        0.7f,       /* Third */
        0.5f,       /* Fifth */
        0.3f,       /* Octave */
        0.4f,       /* Test tone */
        0.2f,       /* Harmonic */
    };

    /* Generate waveform */
    waveform_length = FFT_SIZE;

    for (size_t i = 0; i < waveform_length; i++) {
        float sample = 0.0f;
        float t = (float)i / (float)SAMPLE_RATE_HZ;

        /* Add all frequency components */
        for (int f = 0; f < num_freqs; f++) {
            sample += amplitudes[f] * sinf(2.0f * M_PI * frequencies[f] * t);
        }

        /* Add noise (simple pseudo-random noise) */
        float noise = ((float)(rand() % 1000) / 1000.0f - 0.5f) * 0.3f;
        sample += noise;

        /* Scale to int16_t range with some headroom */
        waveform_buffer[i] = (int16_t)(sample * 4000.0f);
    }

    LOG_INF("Test waveform generated: %d samples", waveform_length);
    LOG_INF("Contains frequencies: 262Hz(C4), 330Hz(E4), 392Hz(G4), 523Hz(C5), 1kHz, 2kHz + noise");
}

/*
 * =============================================================================
 * Display Functions
 * =============================================================================
 */

/**
 * Clear console using ANSI escape codes
 */
static void clear_console(void)
{
    printk("\033[2J\033[H");
}

/**
 * Display waveform information
 */
static void display_waveform_info(void)
{
    printk("\n=== Waveform Information ===\n");
    printk("  Length: %d samples\n", waveform_length);
    printk("  Sample Rate: %d Hz\n", SAMPLE_RATE_HZ);
    printk("  Duration: %.3f seconds\n", (float)waveform_length / SAMPLE_RATE_HZ);
    
    /* Calculate statistics */
    int16_t min = INT16_MAX, max = INT16_MIN;
    int64_t sum = 0;
    
    for (size_t i = 0; i < waveform_length; i++) {
        if (waveform_buffer[i] < min) min = waveform_buffer[i];
        if (waveform_buffer[i] > max) max = waveform_buffer[i];
        sum += waveform_buffer[i];
    }
    
    printk("  Min: %d, Max: %d, Avg: %d\n", min, max, (int32_t)(sum / waveform_length));
    printk("\n");
}

/**
 * Display ASCII spectrum analyzer
 */
static void display_spectrum(void)
{
    printk("\n");
    printk("╔════════════════════════════════════════════════════════════════════╗\n");
    printk("║           FFT SPECTRUM ANALYZER v1.0 - nRF54L15                    ║\n");
    printk("╠════════════════════════════════════════════════════════════════════╣\n");
    printk("║  Sample Rate: %5d Hz  |  FFT Size: %4d  |  Resolution: %4.1f Hz  ║\n",
           SAMPLE_RATE_HZ, FFT_SIZE, (float)SAMPLE_RATE_HZ / FFT_SIZE);
    printk("╚════════════════════════════════════════════════════════════════════╝\n");
    printk("\n");

    /* Find max magnitude for normalization */
    float max_mag = 0.0f;
    for (size_t i = 1; i < FFT_SIZE / 2; i++) {  /* Skip DC (i=0) */
        if (magnitude_spectrum[i] > max_mag) {
            max_mag = magnitude_spectrum[i];
        }
    }

    if (max_mag == 0.0f) max_mag = 1.0f;  /* Avoid division by zero */

    /* Convert to dB scale for better visualization */
    float db_spectrum[FFT_SIZE / 2];
    float max_db = -100.0f;
    
    for (size_t i = 0; i < FFT_SIZE / 2; i++) {
        if (magnitude_spectrum[i] > 0.0001f) {
            db_spectrum[i] = 20.0f * log10f(magnitude_spectrum[i] / max_mag);
        } else {
            db_spectrum[i] = -100.0f;
        }
        if (db_spectrum[i] > max_db) max_db = db_spectrum[i];
    }

    /* Display spectrum as horizontal bars */
    printk("Frequency Spectrum (dB scale, showing top frequencies):\n");
    printk("────────────────────────────────────────────────────────────────────\n");

    /* Find and display top peaks */
    typedef struct {
        size_t bin;
        float magnitude;
        float frequency;
    } peak_t;

    peak_t peaks[10];
    for (int i = 0; i < 10; i++) {
        peaks[i].bin = 0;
        peaks[i].magnitude = 0.0f;
        peaks[i].frequency = 0.0f;
    }

    /* Find top 10 peaks (skip DC) */
    for (size_t i = 1; i < FFT_SIZE / 2; i++) {
        float freq = (float)i * SAMPLE_RATE_HZ / FFT_SIZE;
        
        for (int p = 0; p < 10; p++) {
            if (magnitude_spectrum[i] > peaks[p].magnitude) {
                /* Shift lower peaks down */
                for (int q = 9; q > p; q--) {
                    peaks[q] = peaks[q-1];
                }
                peaks[p].bin = i;
                peaks[p].magnitude = magnitude_spectrum[i];
                peaks[p].frequency = freq;
                break;
            }
        }
    }

    /* Display peaks with bar chart */
    printk("\nTop Frequency Components:\n\n");
    printk("  Freq (Hz)   Bin   Magnitude   dB     Spectrum Bar\n");
    printk("  ─────────   ───   ─────────   ────   ──────────────────────────────\n");

    for (int p = 0; p < 10 && peaks[p].magnitude > 0.01f; p++) {
        float normalized = peaks[p].magnitude / max_mag;
        int bar_len = (int)(normalized * 30);
        if (bar_len > 30) bar_len = 30;
        
        float db = 20.0f * log10f(normalized + 0.0001f);
        
        printk("  %7.1f   %4d   %9.1f   %5.1f   [", 
               peaks[p].frequency, peaks[p].bin, peaks[p].magnitude, db);
        
        for (int b = 0; b < bar_len; b++) {
            if (b < 10) printk("█");
            else if (b < 20) printk("▓");
            else printk("░");
        }
        for (int b = bar_len; b < 30; b++) {
            printk(" ");
        }
        printk("]\n");
    }

    /* Display full spectrum as ASCII art */
    printk("\n\nFull Spectrum Visualization:\n");
    printk("────────────────────────────────────────────────────────────────────\n");
    
    /* Downsample spectrum to fit display width */
    int bins_per_column = (FFT_SIZE / 2) / SPECTRUM_WIDTH;
    if (bins_per_column < 1) bins_per_column = 1;

    /* Draw spectrum (top to bottom) */
    for (int row = SPECTRUM_HEIGHT - 1; row >= 0; row--) {
        /* Y-axis label */
        int db_level = -60 + (row * 60 / SPECTRUM_HEIGHT);
        printk("%4ddB│", db_level);
        
        for (int col = 0; col < SPECTRUM_WIDTH; col++) {
            /* Average magnitude for this column */
            float col_max = 0.0f;
            int start_bin = col * bins_per_column;
            int end_bin = start_bin + bins_per_column;
            if (end_bin > FFT_SIZE / 2) end_bin = FFT_SIZE / 2;
            
            for (int b = start_bin; b < end_bin; b++) {
                if (db_spectrum[b] > col_max || col_max == 0.0f) {
                    col_max = db_spectrum[b];
                }
            }
            
            /* Map to display height */
            int level = (int)((col_max + 60.0f) * SPECTRUM_HEIGHT / 60.0f);
            
            if (level >= row) {
                if (row > SPECTRUM_HEIGHT * 0.8f) printk("█");
                else if (row > SPECTRUM_HEIGHT * 0.5f) printk("▓");
                else if (row > SPECTRUM_HEIGHT * 0.3f) printk("▒");
                else printk("░");
            } else {
                printk(" ");
            }
        }
        printk("│\n");
    }
    
    /* X-axis */
    printk("     └");
    for (int i = 0; i < SPECTRUM_WIDTH; i++) printk("─");
    printk("┘\n");
    
    /* Frequency labels */
    printk("      0");
    for (int i = 0; i < SPECTRUM_WIDTH - 14; i++) printk(" ");
    printk("%d Hz\n", SAMPLE_RATE_HZ / 2);

    printk("\n────────────────────────────────────────────────────────────────────\n");
}

/**
 * Display raw FFT data (first few bins)
 */
static void display_raw_fft_data(void)
{
    printk("\nRaw FFT Data (first 32 frequency bins):\n");
    printk("────────────────────────────────────────────────────────────────────\n");
    printk("  Bin   Freq(Hz)    Real        Imag        Magnitude\n");
    printk("  ───   ────────    ────────    ────────    ─────────\n");
    
    for (int i = 0; i < 32 && i < FFT_SIZE / 2; i++) {
        float freq = (float)i * SAMPLE_RATE_HZ / FFT_SIZE;
        printk("  %3d   %7.1f    %8.1f    %8.1f    %9.1f\n",
               i, freq, fft_output[i].real, fft_output[i].imag, magnitude_spectrum[i]);
    }
    printk("\n");
}

/*
 * =============================================================================
 * UART Upload Functions
 * =============================================================================
 */

/**
 * UART receive callback for waveform upload
 */
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
                /* Receiving 2-byte length (little-endian) */
                if (bytes_received == 0) {
                    expected_bytes = c;
                    bytes_received = 1;
                } else {
                    expected_bytes |= ((size_t)c << 8);
                    bytes_received = 0;
                    
                    if (expected_bytes > MAX_WAVEFORM_SIZE * 2) {
                        LOG_ERR("Waveform too large: %d bytes", expected_bytes);
                        current_state = STATE_IDLE;
                    } else {
                        LOG_INF("Expecting %d bytes of waveform data", expected_bytes);
                        waveform_length = expected_bytes / 2;
                        current_state = STATE_RECEIVING_DATA;
                    }
                }
                break;

            case STATE_RECEIVING_DATA:
                /* Receiving waveform samples (16-bit little-endian) */
                {
                    size_t sample_idx = bytes_received / 2;
                    size_t byte_pos = bytes_received % 2;
                    
                    if (byte_pos == 0) {
                        waveform_buffer[sample_idx] = c;
                    } else {
                        waveform_buffer[sample_idx] |= ((int16_t)c << 8);
                    }
                    
                    bytes_received++;
                    
                    if (bytes_received >= expected_bytes) {
                        LOG_INF("Waveform upload complete: %d samples", waveform_length);
                        current_state = STATE_PROCESSING;
                        bytes_received = 0;
                    }
                }
                break;

            default:
                /* Check for upload start command 'U' */
                if (c == 'U') {
                    LOG_INF("Starting waveform upload...");
                    current_state = STATE_WAITING_LENGTH;
                    bytes_received = 0;
                    expected_bytes = 0;
                }
                /* Check for test waveform command 'T' */
                else if (c == 'T') {
                    LOG_INF("Generating test waveform...");
                    generate_test_waveform();
                    current_state = STATE_PROCESSING;
                }
                /* Check for FFT command 'F' */
                else if (c == 'F') {
                    if (waveform_length > 0) {
                        current_state = STATE_PROCESSING;
                    } else {
                        LOG_WRN("No waveform loaded. Press 'T' for test waveform or 'U' to upload.");
                    }
                }
                break;
        }
    }
}

/**
 * Initialize UART for waveform upload
 */
static int uart_init(void)
{
    uart_dev = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));
    
    if (!device_is_ready(uart_dev)) {
        LOG_ERR("UART device not ready");
        return -ENODEV;
    }

    /* Configure UART interrupt for receive */
    uart_irq_callback_set(uart_dev, uart_rx_callback);
    uart_irq_rx_enable(uart_dev);

    LOG_INF("UART initialized for waveform upload");
    return 0;
}

/*
 * =============================================================================
 * FFT Processing
 * =============================================================================
 */

/**
 * Perform complete FFT analysis on the stored waveform
 */
static void perform_fft_analysis(void)
{
    LOG_INF("Performing FFT analysis...");

    /* Determine FFT input size (use FFT_SIZE or waveform_length, whichever is smaller) */
    size_t fft_samples = (waveform_length < FFT_SIZE) ? waveform_length : FFT_SIZE;

    /* Apply windowing and prepare complex input */
    LOG_INF("Applying Hanning window...");
    apply_hanning_window(waveform_buffer, fft_input, fft_samples);

    /* Zero-pad if waveform is smaller than FFT size */
    for (size_t i = fft_samples; i < FFT_SIZE; i++) {
        fft_input[i].real = 0.0f;
        fft_input[i].imag = 0.0f;
    }

    /* Copy to output buffer for in-place FFT */
    memcpy(fft_output, fft_input, FFT_SIZE * sizeof(complex_t));

    /* Compute FFT */
    LOG_INF("Computing FFT (%d points)...", FFT_SIZE);
    fft_compute(fft_output, FFT_SIZE);

    /* Calculate magnitude spectrum */
    LOG_INF("Calculating magnitude spectrum...");
    calculate_magnitude_spectrum(fft_output, magnitude_spectrum, FFT_SIZE);

    LOG_INF("FFT analysis complete");
}

/*
 * =============================================================================
 * Main Application
 * =============================================================================
 */

/**
 * Display help menu
 */
static void display_menu(void)
{
    printk("\n");
    printk("╔════════════════════════════════════════════════════════════════════╗\n");
    printk("║     FFT WAVEFORM ANALYZER v1.0 - Cochlear Implant Project          ║\n");
    printk("║                      Target: nRF54L15                              ║\n");
    printk("╠════════════════════════════════════════════════════════════════════╣\n");
    printk("║                                                                    ║\n");
    printk("║  Commands:                                                         ║\n");
    printk("║    T - Generate test waveform (song with noise simulation)         ║\n");
    printk("║    U - Upload waveform via UART (send 'U' + 2-byte len + data)     ║\n");
    printk("║    F - Run FFT analysis on current waveform                        ║\n");
    printk("║    H - Show this help menu                                         ║\n");
    printk("║                                                                    ║\n");
    printk("║  Upload Protocol:                                                  ║\n");
    printk("║    1. Send 'U' character                                           ║\n");
    printk("║    2. Send 2-byte length (little-endian, in bytes)                 ║\n");
    printk("║    3. Send waveform data (16-bit signed samples, little-endian)    ║\n");
    printk("║                                                                    ║\n");
    printk("║  Waveform Status: ");
    if (waveform_length > 0) {
        printk("%4d samples loaded                             ║\n", waveform_length);
    } else {
        printk("No waveform loaded                            ║\n");
    }
    printk("║                                                                    ║\n");
    printk("╚════════════════════════════════════════════════════════════════════╝\n");
    printk("\n");
}

int main(void)
{
    int ret;

    /* Initialize random seed for noise generation */
    srand(k_uptime_get_32());

    LOG_INF("═══════════════════════════════════════════════════════════════");
    LOG_INF("  FFT Waveform Analyzer v1.0 - Cochlear Implant Project");
    LOG_INF("  Target: nRF54L15");
    LOG_INF("═══════════════════════════════════════════════════════════════");

    /* Small delay for system stabilization */
    k_sleep(K_MSEC(100));

    /* Initialize UART for waveform upload */
    ret = uart_init();
    if (ret < 0) {
        LOG_WRN("UART init failed, upload disabled");
    }

    /* Display menu */
    display_menu();

    /* Generate initial test waveform automatically */
    LOG_INF("Auto-generating test waveform for demonstration...");
    generate_test_waveform();
    
    /* Perform initial FFT */
    perform_fft_analysis();
    
    /* Display results */
    clear_console();
    display_waveform_info();
    display_spectrum();
    display_raw_fft_data();
    display_menu();

    /* Main loop - wait for commands */
    LOG_INF("Ready for commands. Press 'H' for help.");

    while (1) {
        /* Check if processing was triggered */
        if (current_state == STATE_PROCESSING) {
            current_state = STATE_IDLE;
            
            if (waveform_length > 0) {
                /* Perform FFT analysis */
                perform_fft_analysis();
                
                /* Display results */
                clear_console();
                display_waveform_info();
                display_spectrum();
                display_raw_fft_data();
                display_menu();
            }
        }

        /* Check for 'H' key (help) via polling */
        uint8_t c;
        if (uart_poll_in(uart_dev, &c) == 0) {
            if (c == 'H' || c == 'h') {
                display_menu();
            }
        }

        /* Small delay to prevent busy-waiting */
        k_sleep(K_MSEC(100));
    }

    return 0;
}
