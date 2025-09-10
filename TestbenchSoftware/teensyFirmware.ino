// teensy_firmware.ino

// Define which algorithm is active
enum Algorithm {
  PASSTHROUGH,
  WDRC,
  NOISE_REDUCTION,
  FREQ_SHAPING
};
Algorithm current_algorithm = PASSTHROUGH;

const int BUFFER_SIZE = 256; // Must match CHUNK_SIZE in Python
int16_t sample_buffer[BUFFER_SIZE];

void setup() {
  Serial.begin(115200);
  while (!Serial); // Wait for serial connection
}

void loop() {
  // 1. Check for a command from the Python script
  if (Serial.available() > 0) {
    String command = Serial.readStringUntil('\n');
    command.trim();
    
    if (command == "PASSTHROUGH") {
      current_algorithm = PASSTHROUGH;
    } else if (command == "WDRC") {
      current_algorithm = WDRC;
    } else if (command == "NOISE_REDUCTION") {
      current_algorithm = NOISE_REDUCTION;
    } else if (command == "FREQ_SHAPING") {
      current_algorithm = FREQ_SHAPING;
    }
  }
  
  // 2. Wait for and process a chunk of audio data
  // 2 bytes per 16-bit sample
  if (Serial.available() >= BUFFER_SIZE * 2) {
    Serial.readBytes((char*)sample_buffer, BUFFER_SIZE * 2);

    // Apply the selected algorithm
    for (int i = 0; i < BUFFER_SIZE; i++) {
      switch (current_algorithm) {
        case PASSTHROUGH:
          // Do nothing, just pass it through
          break;
        case WDRC:
          sample_buffer[i] = process_wdrc(sample_buffer[i]);
          break;
        case NOISE_REDUCTION:
          sample_buffer[i] = process_noise_reduction(sample_buffer[i]);
          break;
        case FREQ_SHAPING:
          // Note: True freq shaping needs FFTs or filter banks. This is a placeholder.
          sample_buffer[i] = process_freq_shaping(sample_buffer[i]);
          break;
      }
    }

    // 3. Send the processed data back to Python
    Serial.write((uint8_t*)sample_buffer, BUFFER_SIZE * 2);
  }
}


// --- SIMPLIFIED ALGORITHM IMPLEMENTATIONS ---

// A very basic WDRC: amplifies quiet sounds more than loud sounds.
int16_t process_wdrc(int16_t sample) {
  const int16_t threshold = 4000; // Compression starts for samples above this magnitude
  const float ratio = 2.0;       // 2:1 compression ratio
  const float gain = 1.5;        // Makeup gain

  long sample_long = sample;
  
  if (abs(sample_long) < threshold) {
    // Apply linear gain below threshold
    sample_long *= (gain * 1.2); 
  } else {
    // Apply compression above threshold
    long excess = abs(sample_long) - threshold;
    sample_long = (sample_long > 0 ? 1 : -1) * (threshold + (long)(excess / ratio));
    sample_long *= gain; // Apply makeup gain
  }

  // Clip to prevent overflow
  if (sample_long > 32767) sample_long = 32767;
  if (sample_long < -32768) sample_long = -32768;
  
  return (int16_t)sample_long;
}

// A very basic "noise reduction" via a simple low-pass filter to cut hiss.
// A real NR algorithm is much more complex (e.g., spectral subtraction).
int16_t process_noise_reduction(int16_t sample) {
  static int16_t last_output = 0;
  const float alpha = 0.4; // Filter coefficient
  int16_t output = alpha * sample + (1.0 - alpha) * last_output;
  last_output = output;
  return output;
}

// A placeholder for frequency shaping. This just applies a simple gain.
// A real implementation would use FFTs or a bank of IIR/FIR filters.
int16_t process_freq_shaping(int16_t sample) {
  const float high_freq_boost = 1.8; // Example: Boost high frequencies
  // This is a crude high-pass filter to simulate boosting highs.
  static int16_t last_input = 0;
  long output_long = high_freq_boost * (long)(sample - last_input);
  last_input = sample;
  
  if (output_long > 32767) output_long = 32767;
  if (output_long < -32768) output_long = -32768;

  return (int16_t)output_long;
}