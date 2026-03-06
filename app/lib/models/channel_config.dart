import 'dart:typed_data';

/// Per-channel WDRC compression configuration.
///
/// Maps 1:1 with the firmware's channel_config_wire_t (24 bytes packed).
/// 12 channels cover frequencies from 200 Hz to 7500 Hz.
class ChannelConfig {
  final int index;
  final double centerFreqHz;
  double gainDb;
  double thresholdDb;
  double ratio;
  double attackMs;
  double releaseMs;
  double mpoDbSpl;

  /// The 12 channel center frequencies matching the firmware.
  static const List<double> channelCenterFreqs = [
    200, 315, 500, 800, 1000, 1500,
    2000, 3000, 4000, 5000, 6000, 7500,
  ];

  /// Wire size of one channel_config_wire_t (6 x float32 = 24 bytes).
  static const int wireSize = 24;

  ChannelConfig({
    required this.index,
    required this.centerFreqHz,
    this.gainDb = 0.0,
    this.thresholdDb = -35.0,
    this.ratio = 2.0,
    this.attackMs = 5.0,
    this.releaseMs = 50.0,
    this.mpoDbSpl = 110.0,
  });

  /// Create default configs for all 12 channels.
  static List<ChannelConfig> createDefaults() {
    return List.generate(12, (i) => ChannelConfig(
      index: i,
      centerFreqHz: channelCenterFreqs[i],
    ));
  }

  /// Compute the effective gain for a given input level (dB),
  /// modeling the WDRC compression curve.
  double computeGainAtInput(double inputDb) {
    if (inputDb < thresholdDb) {
      return gainDb;
    }
    final excessDb = inputDb - thresholdDb;
    final compressedExcess = excessDb / ratio;
    final outputDb = thresholdDb + compressedExcess;
    return outputDb - inputDb + gainDb;
  }

  /// Compute output level for a given input level.
  double computeOutputAtInput(double inputDb) {
    return inputDb + computeGainAtInput(inputDb);
  }

  /// Serialize to firmware binary format (24 bytes, little-endian floats).
  Uint8List toBytes() {
    final data = ByteData(wireSize);
    data.setFloat32(0, gainDb, Endian.little);
    data.setFloat32(4, thresholdDb, Endian.little);
    data.setFloat32(8, ratio, Endian.little);
    data.setFloat32(12, attackMs, Endian.little);
    data.setFloat32(16, releaseMs, Endian.little);
    data.setFloat32(20, mpoDbSpl, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Deserialize from firmware binary format.
  factory ChannelConfig.fromBytes(int index, Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return ChannelConfig(
      index: index,
      centerFreqHz: channelCenterFreqs[index],
      gainDb: data.getFloat32(0, Endian.little),
      thresholdDb: data.getFloat32(4, Endian.little),
      ratio: data.getFloat32(8, Endian.little),
      attackMs: data.getFloat32(12, Endian.little),
      releaseMs: data.getFloat32(16, Endian.little),
      mpoDbSpl: data.getFloat32(20, Endian.little),
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'centerFreqHz': centerFreqHz,
        'gainDb': gainDb,
        'thresholdDb': thresholdDb,
        'ratio': ratio,
        'attackMs': attackMs,
        'releaseMs': releaseMs,
        'mpoDbSpl': mpoDbSpl,
      };

  factory ChannelConfig.fromJson(Map<String, dynamic> json) {
    final idx = json['index'] as int;
    return ChannelConfig(
      index: idx,
      centerFreqHz: (json['centerFreqHz'] as num).toDouble(),
      gainDb: (json['gainDb'] as num).toDouble(),
      thresholdDb: (json['thresholdDb'] as num).toDouble(),
      ratio: (json['ratio'] as num).toDouble(),
      attackMs: (json['attackMs'] as num).toDouble(),
      releaseMs: (json['releaseMs'] as num).toDouble(),
      mpoDbSpl: (json['mpoDbSpl'] as num).toDouble(),
    );
  }

  ChannelConfig copyWith({
    double? gainDb,
    double? thresholdDb,
    double? ratio,
    double? attackMs,
    double? releaseMs,
    double? mpoDbSpl,
  }) {
    return ChannelConfig(
      index: index,
      centerFreqHz: centerFreqHz,
      gainDb: gainDb ?? this.gainDb,
      thresholdDb: thresholdDb ?? this.thresholdDb,
      ratio: ratio ?? this.ratio,
      attackMs: attackMs ?? this.attackMs,
      releaseMs: releaseMs ?? this.releaseMs,
      mpoDbSpl: mpoDbSpl ?? this.mpoDbSpl,
    );
  }
}
