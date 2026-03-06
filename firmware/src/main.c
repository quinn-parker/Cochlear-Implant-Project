/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cochlear Implant Project - PDM Microphone Waveform Test
 * Target: nRF54L15
 *
 * This skeleton reads PDM microphone data and outputs the waveform
 * to the serial console for visualization.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <nrfx_pdm.h>
#include <string.h>
#include <math.h>

LOG_MODULE_REGISTER(mic_test, LOG_LEVEL_INF);

/*
 * =============================================================================
 * Configuration - Infineon IM69D129F PDM Microphone
 * =============================================================================
 *
 * IM69D129F Key Specifications:
 * - SNR: 69 dB (A-weighted)
 * - AOP: 128 dB SPL (high dynamic range - great for hearing aids)
 * - Sensitivity: -36 dBFS @ 94 dB SPL
 * - PDM Clock: 1.0 MHz to 3.25 MHz (optimal ~2.4 MHz)
 * - Supply: 1.62V to 3.6V
 * - Current: ~650 µA active
 *
 * L/R Pin Configuration:
 * - L/R = LOW (GND):  Data valid on FALLING edge (Left channel timing)
 * - L/R = HIGH (VDD): Data valid on RISING edge (Right channel timing)
 */

/* PDM pin configuration - adjust these for your hardware */
#define PDM_CLK_PIN     NRF_GPIO_PIN_MAP(1, 10)  /* P1.10 - PDM Clock */
#define PDM_DATA_PIN    NRF_GPIO_PIN_MAP(1, 11)  /* P1.11 - PDM Data */

/*
 * IM69D129F L/R pin configuration:
 * Set to 1 if L/R pin is tied HIGH (data on rising edge)
 * Set to 0 if L/R pin is tied LOW (data on falling edge)
 */
#define IM69D129_LR_HIGH    0

/* Audio sample configuration */
#define SAMPLE_RATE_HZ      16000   /* 16 kHz sample rate */
#define AUDIO_BUFFER_SAMPLES 256    /* Samples per buffer */
#define NUM_BUFFERS         2       /* Double buffering */

/* Waveform display configuration */
#define WAVEFORM_WIDTH      64      /* ASCII waveform width in characters */
#define DISPLAY_INTERVAL_MS 100     /* How often to update display */
#define DOWNSAMPLE_FACTOR   8       /* Reduce samples for display */

/*
 * =============================================================================
 * Audio Buffers
 * =============================================================================
 */

static int16_t audio_buffer_0[AUDIO_BUFFER_SAMPLES];
static int16_t audio_buffer_1[AUDIO_BUFFER_SAMPLES];
static int16_t *current_buffer = audio_buffer_0;
static volatile bool buffer_ready = false;
static volatile uint8_t active_buffer = 0;

/*
 * =============================================================================
 * PDM Event Handler
 * =============================================================================
 */

static void pdm_event_handler(nrfx_pdm_evt_t const *p_evt)
{
    if (p_evt->error != NRFX_PDM_NO_ERROR) {
        LOG_ERR("PDM error: %d", p_evt->error);
        return;
    }

    if (p_evt->buffer_released != NULL) {
        /* A buffer has been filled and released */
        current_buffer = (int16_t *)p_evt->buffer_released;
        buffer_ready = true;
    }

    if (p_evt->buffer_requested) {
        /* PDM driver needs a new buffer - provide the next one */
        int16_t *next_buffer;
        if (active_buffer == 0) {
            next_buffer = audio_buffer_1;
            active_buffer = 1;
        } else {
            next_buffer = audio_buffer_0;
            active_buffer = 0;
        }
        
        nrfx_err_t err = nrfx_pdm_buffer_set(next_buffer, AUDIO_BUFFER_SAMPLES);
        if (err != NRFX_SUCCESS) {
            LOG_ERR("Failed to set PDM buffer: 0x%x", err);
        }
    }
}

/*
 * =============================================================================
 * PDM Initialization
 * =============================================================================
 */

static int pdm_init(void)
{
    nrfx_err_t err;

    /*
     * Configure PDM for Infineon IM69D129F
     *
     * Clock frequency selection:
     * - IM69D129F supports 1.0 - 3.25 MHz, optimal around 2.4 MHz
     * - NRF_PDM_FREQ_1280K = 1.28 MHz (good balance of quality/power)
     * - NRF_PDM_FREQ_1067K = 1.067 MHz (lower power)
     * 
     * With RATIO_80X and 1.28 MHz clock: sample rate = 1.28M / 80 = 16 kHz
     * With RATIO_64X and 1.024 MHz clock: sample rate = 1.024M / 64 = 16 kHz
     *
     * Edge selection based on L/R pin:
     * - L/R LOW:  Use NRF_PDM_EDGE_LEFTFALLING
     * - L/R HIGH: Use NRF_PDM_EDGE_LEFTRISING
     */
    nrfx_pdm_config_t pdm_config = {
        .mode = NRF_PDM_MODE_MONO,
#if IM69D129_LR_HIGH
        .edge = NRF_PDM_EDGE_LEFTRISING,   /* L/R pin HIGH: data on rising edge */
#else
        .edge = NRF_PDM_EDGE_LEFTFALLING,  /* L/R pin LOW: data on falling edge */
#endif
        .clk_pin = PDM_CLK_PIN,
        .din_pin = PDM_DATA_PIN,
        .clock_freq = NRF_PDM_FREQ_1280K,  /* 1.28 MHz - within IM69D129F range */
        .gain_l = NRF_PDM_GAIN_DEFAULT,    /* 0 dB gain - IM69D129F has good sensitivity */
        .gain_r = NRF_PDM_GAIN_DEFAULT,
        .ratio = NRF_PDM_RATIO_80X,        /* 1.28 MHz / 80 = 16 kHz sample rate */
        .skip_gpio_cfg = false,
        .skip_psel_cfg = false,
    };

    /* Initialize PDM driver */
    err = nrfx_pdm_init(&pdm_config, pdm_event_handler);
    if (err != NRFX_SUCCESS) {
        LOG_ERR("PDM init failed: 0x%x", err);
        return -EIO;
    }

    LOG_INF("PDM initialized for Infineon IM69D129F");
    LOG_INF("  Clock: 1.28 MHz, Sample rate: %d Hz", SAMPLE_RATE_HZ);
#if IM69D129_LR_HIGH
    LOG_INF("  L/R config: HIGH (rising edge)");
#else
    LOG_INF("  L/R config: LOW (falling edge)");
#endif
    return 0;
}

/*
 * =============================================================================
 * PDM Start/Stop
 * =============================================================================
 */

static int pdm_start(void)
{
    nrfx_err_t err;

    /* Set initial buffer */
    err = nrfx_pdm_buffer_set(audio_buffer_0, AUDIO_BUFFER_SAMPLES);
    if (err != NRFX_SUCCESS) {
        LOG_ERR("Failed to set initial PDM buffer: 0x%x", err);
        return -EIO;
    }

    /* Start PDM sampling */
    err = nrfx_pdm_start();
    if (err != NRFX_SUCCESS) {
        LOG_ERR("PDM start failed: 0x%x", err);
        return -EIO;
    }

    LOG_INF("PDM started - sampling at %d Hz", SAMPLE_RATE_HZ);
    return 0;
}

/*
 * =============================================================================
 * Waveform Display Functions
 * =============================================================================
 */

/**
 * Calculate audio statistics from buffer
 */
static void calculate_audio_stats(int16_t *buffer, size_t len, 
                                   int16_t *min, int16_t *max, int32_t *avg)
{
    *min = INT16_MAX;
    *max = INT16_MIN;
    int64_t sum = 0;

    for (size_t i = 0; i < len; i++) {
        if (buffer[i] < *min) *min = buffer[i];
        if (buffer[i] > *max) *max = buffer[i];
        sum += buffer[i];
    }

    *avg = (int32_t)(sum / len);
}

/**
 * Calculate RMS (Root Mean Square) level - useful for audio level metering
 */
static uint32_t calculate_rms(int16_t *buffer, size_t len)
{
    uint64_t sum_sq = 0;
    
    for (size_t i = 0; i < len; i++) {
        int32_t sample = buffer[i];
        sum_sq += (sample * sample);
    }
    
    return (uint32_t)sqrt((double)sum_sq / len);
}

/**
 * Print an ASCII waveform to the console
 */
static void print_waveform(int16_t *buffer, size_t len)
{
    char line[WAVEFORM_WIDTH + 3];  /* +3 for '|' chars and null terminator */
    
    /* Clear screen and move cursor to top (ANSI escape) */
    printk("\033[2J\033[H");
    
    printk("=== PDM Microphone Waveform Test ===\n");
    printk("Sample Rate: %d Hz | Buffer: %d samples\n\n", 
           SAMPLE_RATE_HZ, AUDIO_BUFFER_SAMPLES);

    /* Calculate statistics */
    int16_t min, max;
    int32_t avg;
    calculate_audio_stats(buffer, len, &min, &max, &avg);
    uint32_t rms = calculate_rms(buffer, len);

    printk("Stats: Min=%6d  Max=%6d  Avg=%6d  RMS=%5u\n\n", 
           min, max, avg, rms);

    /* Print ASCII waveform - downsample for display */
    printk("Waveform (downsampled %dx):\n", DOWNSAMPLE_FACTOR);
    
    size_t display_samples = len / DOWNSAMPLE_FACTOR;
    if (display_samples > WAVEFORM_WIDTH) {
        display_samples = WAVEFORM_WIDTH;
    }

    /* Normalize samples to 0-WAVEFORM_WIDTH range for display */
    int16_t range = max - min;
    if (range == 0) range = 1;  /* Avoid division by zero */

    /* Print top border */
    printk("+");
    for (int i = 0; i < WAVEFORM_WIDTH; i++) printk("-");
    printk("+\n");

    /* Print waveform as vertical bars centered around middle */
    const int height = 16;  /* ASCII waveform height */
    
    for (int row = height - 1; row >= 0; row--) {
        printk("|");
        
        for (size_t col = 0; col < display_samples; col++) {
            size_t idx = col * DOWNSAMPLE_FACTOR;
            
            /* Normalize sample to 0-height range */
            int normalized = ((buffer[idx] - min) * height) / range;
            
            if (normalized >= row) {
                printk("#");
            } else {
                printk(" ");
            }
        }
        
        /* Pad remaining columns */
        for (size_t col = display_samples; col < WAVEFORM_WIDTH; col++) {
            printk(" ");
        }
        
        printk("|\n");
    }

    /* Print bottom border */
    printk("+");
    for (int i = 0; i < WAVEFORM_WIDTH; i++) printk("-");
    printk("+\n");

    /* Print raw sample values (first few) */
    printk("\nRaw samples (first 16):\n");
    for (int i = 0; i < 16 && i < len; i++) {
        printk("%6d ", buffer[i]);
        if ((i + 1) % 8 == 0) printk("\n");
    }
    printk("\n");

    /* Print level meter */
    printk("\nLevel: [");
    int level_bars = (rms * 32) / 32768;
    if (level_bars > 32) level_bars = 32;
    for (int i = 0; i < 32; i++) {
        if (i < level_bars) {
            if (i < 20) printk("=");
            else if (i < 28) printk("*");
            else printk("!");
        } else {
            printk(" ");
        }
    }
    printk("] %u\n", rms);
}

/**
 * Print raw samples as CSV (useful for plotting in external tools)
 */
static void print_samples_csv(int16_t *buffer, size_t len)
{
    printk("\n--- CSV START ---\n");
    for (size_t i = 0; i < len; i++) {
        printk("%d\n", buffer[i]);
    }
    printk("--- CSV END ---\n");
}

/*
 * =============================================================================
 * Main Application
 * =============================================================================
 */

int main(void)
{
    int ret;

    LOG_INF("Cochlear Implant Project - PDM Microphone Test");
    LOG_INF("Target: nRF54L15");
    LOG_INF("Starting up...");

    /* Small delay for system stabilization */
    k_sleep(K_MSEC(100));

    /* Initialize PDM */
    ret = pdm_init();
    if (ret < 0) {
        LOG_ERR("Failed to initialize PDM microphone!");
        LOG_ERR("Check pin configuration:");
        LOG_ERR("  CLK: P%d.%d", PDM_CLK_PIN >> 5, PDM_CLK_PIN & 0x1F);
        LOG_ERR("  DATA: P%d.%d", PDM_DATA_PIN >> 5, PDM_DATA_PIN & 0x1F);
        return ret;
    }

    /* Start PDM sampling */
    ret = pdm_start();
    if (ret < 0) {
        LOG_ERR("Failed to start PDM!");
        return ret;
    }

    LOG_INF("PDM microphone running - displaying waveform...");
    LOG_INF("Press any key to output CSV format");

    /* Main loop - display waveform when buffer is ready */
    uint32_t frame_count = 0;
    bool csv_mode = false;

    while (1) {
        if (buffer_ready) {
            buffer_ready = false;
            frame_count++;

            if (csv_mode) {
                /* Output raw CSV for external analysis */
                print_samples_csv(current_buffer, AUDIO_BUFFER_SAMPLES);
                k_sleep(K_MSEC(1000));  /* Slower rate for CSV */
            } else {
                /* Display ASCII waveform */
                print_waveform(current_buffer, AUDIO_BUFFER_SAMPLES);
            }

            /* Log periodic status */
            if (frame_count % 100 == 0) {
                LOG_INF("Processed %u audio frames", frame_count);
            }
        }

        /* Small delay to prevent busy-waiting */
        k_sleep(K_MSEC(DISPLAY_INTERVAL_MS));
    }

    return 0;
}
