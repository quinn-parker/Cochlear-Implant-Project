import 'dart:math';
import '../models/audiogram.dart';
import '../models/channel_config.dart';

/// Simplified NAL-NL2-style prescription algorithm.
///
/// Computes initial per-channel gain, compression ratio, threshold,
/// and MPO from a patient's audiogram. The audiologist can then
/// manually fine-tune all parameters after the auto-fit.
class AutofitService {
  static const List<int> audiogramFreqs = [
    250, 500, 1000, 2000, 3000, 4000, 6000, 8000
  ];

  static const List<double> channelCenterFreqs = [
    200, 315, 500, 800, 1000, 1500, 2000, 3000, 4000, 5000, 6000, 7500
  ];

  /// Frequency-dependent gain offset (simplified NAL-NL2 X(f) values).
  /// Positive = more gain prescribed at that frequency.
  static const Map<int, double> _nalXf = {
    250: -2.0,
    500: 0.0,
    1000: -1.0,
    1500: -1.5,
    2000: -2.0,
    3000: 0.0,
    4000: 1.0,
    6000: 1.0,
    8000: 0.0,
  };

  /// Compute prescribed channel configs from audiogram.
  ///
  /// [audiogram] is the ear-specific audiogram data.
  /// [isExperiencedUser] reduces initial gain for new users (NAL-NL2 acclimatization).
  /// [isBilateral] applies bilateral correction (~3 dB less gain).
  static List<ChannelConfig> prescribe(
    AudiogramData audiogram, {
    bool isExperiencedUser = false,
    bool isBilateral = false,
  }) {
    // 1. Compute PTA (pure-tone average: 500, 1000, 2000 Hz)
    final pta = audiogram.pta ?? 30.0;

    // 2. Bilateral correction
    final bilateralOffset = isBilateral ? -3.0 : 0.0;

    // 3. Experience correction (new users get less gain for moderate+ loss)
    final experienceOffset =
        (!isExperiencedUser && pta > 40) ? -5.0 : 0.0;

    // 4. Compute per-channel prescription
    final channels = <ChannelConfig>[];

    for (int i = 0; i < 12; i++) {
      final freq = channelCenterFreqs[i];

      // Interpolate hearing loss at this channel frequency
      final hl = audiogram.getThresholdAt(freq) ?? 25.0;

      // NAL-NL2 simplified gain for 65 dB SPL input:
      // gain_65 = X(f) + 0.31 * HL(f) + correction_factors
      final xf = _interpolateXf(freq);
      final ptaCorrection = 0.05 * (pta - 60.0);
      var prescribedGain =
          xf + 0.31 * hl + ptaCorrection + bilateralOffset + experienceOffset;

      // Clamp gain to reasonable range
      prescribedGain = prescribedGain.clamp(-10.0, 60.0);

      // Derive compression ratio from hearing loss severity
      // Mild -> ~1.3:1, Moderate -> ~2:1, Severe -> ~3:1
      var compressionRatio = 1.0 + (hl / 100.0) * 2.5;
      compressionRatio = compressionRatio.clamp(1.0, 4.0);

      // Threshold: lower threshold for more hearing loss (amplify softer sounds)
      var threshold = -50.0 + (hl * 0.15);
      threshold = threshold.clamp(-60.0, -20.0);

      // MPO: based on estimated uncomfortable loudness level
      // UCL estimate ≈ 100 + 0.25 * HL (Pascoe, 1988 approximation)
      var mpo = 100.0 + hl * 0.25;
      mpo = mpo.clamp(90.0, 130.0);

      // Attack/release: standard speech-optimized values
      const attackMs = 5.0;
      const releaseMs = 50.0;

      channels.add(ChannelConfig(
        index: i,
        centerFreqHz: freq,
        gainDb: _roundTo(prescribedGain, 0.5),
        thresholdDb: _roundTo(threshold, 1.0),
        ratio: _roundTo(compressionRatio, 0.1),
        attackMs: attackMs,
        releaseMs: releaseMs,
        mpoDbSpl: _roundTo(mpo, 1.0),
      ));
    }

    return channels;
  }

  /// Interpolate X(f) gain offset at an arbitrary frequency.
  static double _interpolateXf(double freqHz) {
    final freqs = _nalXf.keys.toList()..sort();
    if (freqHz <= freqs.first) return _nalXf[freqs.first]!;
    if (freqHz >= freqs.last) return _nalXf[freqs.last]!;

    for (int i = 0; i < freqs.length - 1; i++) {
      if (freqHz >= freqs[i] && freqHz <= freqs[i + 1]) {
        final logF = log(freqHz) / ln2;
        final logF1 = log(freqs[i].toDouble()) / ln2;
        final logF2 = log(freqs[i + 1].toDouble()) / ln2;
        final t = (logF - logF1) / (logF2 - logF1);
        return _nalXf[freqs[i]]! + t * (_nalXf[freqs[i + 1]]! - _nalXf[freqs[i]]!);
      }
    }
    return 0.0;
  }

  /// Round to nearest step.
  static double _roundTo(double value, double step) {
    return (value / step).round() * step;
  }

  /// Generate built-in presets.
  static List<ChannelConfig> mildLossPreset() {
    final audiogram = AudiogramData(
      airConduction: {
        250: 20, 500: 25, 1000: 25, 2000: 30,
        3000: 35, 4000: 40, 6000: 40, 8000: 40,
      },
    );
    return prescribe(audiogram);
  }

  static List<ChannelConfig> moderateLossPreset() {
    final audiogram = AudiogramData(
      airConduction: {
        250: 35, 500: 40, 1000: 45, 2000: 50,
        3000: 55, 4000: 60, 6000: 60, 8000: 55,
      },
    );
    return prescribe(audiogram);
  }

  static List<ChannelConfig> severeLossPreset() {
    final audiogram = AudiogramData(
      airConduction: {
        250: 55, 500: 60, 1000: 70, 2000: 75,
        3000: 80, 4000: 85, 6000: 85, 8000: 80,
      },
    );
    return prescribe(audiogram);
  }

  static List<ChannelConfig> highFreqLossPreset() {
    final audiogram = AudiogramData(
      airConduction: {
        250: 10, 500: 15, 1000: 20, 2000: 40,
        3000: 55, 4000: 65, 6000: 70, 8000: 70,
      },
    );
    return prescribe(audiogram);
  }
}
