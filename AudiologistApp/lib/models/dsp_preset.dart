/// Model class for DSP configuration presets
/// 
/// Contains all DSP parameters that can be saved/loaded
class DspPreset {
  final String id;
  final String name;
  final String notes;
  final DateTime createdAt;
  
  // Master
  final double masterVolume;
  
  // EQ
  final double eqLow;
  final double eqLowMid;
  final double eqMid;
  final double eqHighMid;
  final double eqHigh;
  
  // Compression
  final double compressionThreshold;
  final double compressionRatio;
  final double compressionAttack;
  final double compressionRelease;
  
  // Noise Reduction
  final bool noiseReductionEnabled;
  final double noiseReductionStrength;
  
  // Feedback Cancellation
  final bool feedbackCancellationEnabled;
  final double feedbackAdaptationRate;

  DspPreset({
    required this.id,
    required this.name,
    required this.notes,
    required this.createdAt,
    required this.masterVolume,
    required this.eqLow,
    required this.eqLowMid,
    required this.eqMid,
    required this.eqHighMid,
    required this.eqHigh,
    required this.compressionThreshold,
    required this.compressionRatio,
    required this.compressionAttack,
    required this.compressionRelease,
    required this.noiseReductionEnabled,
    required this.noiseReductionStrength,
    required this.feedbackCancellationEnabled,
    required this.feedbackAdaptationRate,
  });

  /// Create from JSON map
  factory DspPreset.fromJson(Map<String, dynamic> json) {
    return DspPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      notes: json['notes'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      masterVolume: (json['masterVolume'] as num).toDouble(),
      eqLow: (json['eqLow'] as num).toDouble(),
      eqLowMid: (json['eqLowMid'] as num).toDouble(),
      eqMid: (json['eqMid'] as num).toDouble(),
      eqHighMid: (json['eqHighMid'] as num).toDouble(),
      eqHigh: (json['eqHigh'] as num).toDouble(),
      compressionThreshold: (json['compressionThreshold'] as num).toDouble(),
      compressionRatio: (json['compressionRatio'] as num).toDouble(),
      compressionAttack: (json['compressionAttack'] as num).toDouble(),
      compressionRelease: (json['compressionRelease'] as num).toDouble(),
      noiseReductionEnabled: json['noiseReductionEnabled'] as bool,
      noiseReductionStrength: (json['noiseReductionStrength'] as num).toDouble(),
      feedbackCancellationEnabled: json['feedbackCancellationEnabled'] as bool,
      feedbackAdaptationRate: (json['feedbackAdaptationRate'] as num).toDouble(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'masterVolume': masterVolume,
      'eqLow': eqLow,
      'eqLowMid': eqLowMid,
      'eqMid': eqMid,
      'eqHighMid': eqHighMid,
      'eqHigh': eqHigh,
      'compressionThreshold': compressionThreshold,
      'compressionRatio': compressionRatio,
      'compressionAttack': compressionAttack,
      'compressionRelease': compressionRelease,
      'noiseReductionEnabled': noiseReductionEnabled,
      'noiseReductionStrength': noiseReductionStrength,
      'feedbackCancellationEnabled': feedbackCancellationEnabled,
      'feedbackAdaptationRate': feedbackAdaptationRate,
    };
  }

  /// Create a copy with modified fields
  DspPreset copyWith({
    String? id,
    String? name,
    String? notes,
    DateTime? createdAt,
    double? masterVolume,
    double? eqLow,
    double? eqLowMid,
    double? eqMid,
    double? eqHighMid,
    double? eqHigh,
    double? compressionThreshold,
    double? compressionRatio,
    double? compressionAttack,
    double? compressionRelease,
    bool? noiseReductionEnabled,
    double? noiseReductionStrength,
    bool? feedbackCancellationEnabled,
    double? feedbackAdaptationRate,
  }) {
    return DspPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      masterVolume: masterVolume ?? this.masterVolume,
      eqLow: eqLow ?? this.eqLow,
      eqLowMid: eqLowMid ?? this.eqLowMid,
      eqMid: eqMid ?? this.eqMid,
      eqHighMid: eqHighMid ?? this.eqHighMid,
      eqHigh: eqHigh ?? this.eqHigh,
      compressionThreshold: compressionThreshold ?? this.compressionThreshold,
      compressionRatio: compressionRatio ?? this.compressionRatio,
      compressionAttack: compressionAttack ?? this.compressionAttack,
      compressionRelease: compressionRelease ?? this.compressionRelease,
      noiseReductionEnabled: noiseReductionEnabled ?? this.noiseReductionEnabled,
      noiseReductionStrength: noiseReductionStrength ?? this.noiseReductionStrength,
      feedbackCancellationEnabled: feedbackCancellationEnabled ?? this.feedbackCancellationEnabled,
      feedbackAdaptationRate: feedbackAdaptationRate ?? this.feedbackAdaptationRate,
    );
  }
}
