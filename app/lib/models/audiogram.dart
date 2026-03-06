/// Audiogram data model for clinical hearing assessment.
///
/// Stores pure-tone audiometry thresholds at standard frequencies
/// for both air and bone conduction, per ear.
library;

class AudiogramData {
  /// Standard audiometric test frequencies in Hz.
  static const List<int> standardFrequencies = [
    250, 500, 1000, 2000, 3000, 4000, 6000, 8000
  ];

  /// Air conduction thresholds: frequency (Hz) -> dB HL (null = not tested).
  final Map<int, double?> airConduction;

  /// Bone conduction thresholds: frequency (Hz) -> dB HL (null = not tested).
  final Map<int, double?> boneConduction;

  AudiogramData({
    Map<int, double?>? airConduction,
    Map<int, double?>? boneConduction,
  })  : airConduction = airConduction ??
            {for (var f in standardFrequencies) f: null},
        boneConduction = boneConduction ??
            {for (var f in standardFrequencies) f: null};

  /// Pure-tone average (500, 1000, 2000 Hz air conduction).
  double? get pta {
    final vals = [500, 1000, 2000]
        .map((f) => airConduction[f])
        .whereType<double>()
        .toList();
    if (vals.length < 3) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Get threshold at a specific frequency, interpolating if needed.
  /// Uses log-frequency linear interpolation between measured points.
  double? getThresholdAt(double freqHz) {
    final measured = airConduction.entries
        .where((e) => e.value != null)
        .map((e) => MapEntry(e.key, e.value!))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (measured.isEmpty) return null;
    if (freqHz <= measured.first.key) return measured.first.value;
    if (freqHz >= measured.last.key) return measured.last.value;

    for (int i = 0; i < measured.length - 1; i++) {
      if (freqHz >= measured[i].key && freqHz <= measured[i + 1].key) {
        final logF = _log2(freqHz);
        final logF1 = _log2(measured[i].key.toDouble());
        final logF2 = _log2(measured[i + 1].key.toDouble());
        final t = (logF - logF1) / (logF2 - logF1);
        return measured[i].value + t * (measured[i + 1].value - measured[i].value);
      }
    }
    return null;
  }

  static double _log2(double x) => x > 0 ? log(x) / log(2) : 0;

  /// Hearing loss severity classification at a given frequency.
  static String classifyLoss(double? thresholdDbHl) {
    if (thresholdDbHl == null) return 'Unknown';
    if (thresholdDbHl <= 25) return 'Normal';
    if (thresholdDbHl <= 40) return 'Mild';
    if (thresholdDbHl <= 55) return 'Moderate';
    if (thresholdDbHl <= 70) return 'Moderately Severe';
    if (thresholdDbHl <= 90) return 'Severe';
    return 'Profound';
  }

  Map<String, dynamic> toJson() => {
        'air': airConduction.map((k, v) => MapEntry(k.toString(), v)),
        'bone': boneConduction.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory AudiogramData.fromJson(Map<String, dynamic> json) {
    return AudiogramData(
      airConduction: _parseFreqMap(json['air'] as Map<String, dynamic>?),
      boneConduction: _parseFreqMap(json['bone'] as Map<String, dynamic>?),
    );
  }

  static Map<int, double?> _parseFreqMap(Map<String, dynamic>? json) {
    if (json == null) return {for (var f in standardFrequencies) f: null};
    return json.map(
      (k, v) => MapEntry(int.parse(k), v as double?),
    );
  }

  AudiogramData copyWith({
    Map<int, double?>? airConduction,
    Map<int, double?>? boneConduction,
  }) {
    return AudiogramData(
      airConduction: airConduction ?? Map.from(this.airConduction),
      boneConduction: boneConduction ?? Map.from(this.boneConduction),
    );
  }
}

import 'dart:math';

class PatientAudiogram {
  final AudiogramData left;
  final AudiogramData right;

  PatientAudiogram({
    AudiogramData? left,
    AudiogramData? right,
  })  : left = left ?? AudiogramData(),
        right = right ?? AudiogramData();

  Map<String, dynamic> toJson() => {
        'left': left.toJson(),
        'right': right.toJson(),
      };

  factory PatientAudiogram.fromJson(Map<String, dynamic> json) {
    return PatientAudiogram(
      left: json['left'] != null
          ? AudiogramData.fromJson(json['left'] as Map<String, dynamic>)
          : null,
      right: json['right'] != null
          ? AudiogramData.fromJson(json['right'] as Map<String, dynamic>)
          : null,
    );
  }

  PatientAudiogram copyWith({
    AudiogramData? left,
    AudiogramData? right,
  }) {
    return PatientAudiogram(
      left: left ?? this.left.copyWith(),
      right: right ?? this.right.copyWith(),
    );
  }
}
