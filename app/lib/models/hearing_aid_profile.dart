import 'dart:convert';
import 'dart:typed_data';
import 'audiogram.dart';
import 'channel_config.dart';

/// Metadata for a hearing aid profile.
class ProfileMetadata {
  String patientName;
  String patientId;
  String audiologistName;
  String clinicName;
  DateTime dateCreated;
  DateTime dateModified;
  String notes;

  ProfileMetadata({
    this.patientName = '',
    this.patientId = '',
    this.audiologistName = '',
    this.clinicName = '',
    DateTime? dateCreated,
    DateTime? dateModified,
    this.notes = '',
  })  : dateCreated = dateCreated ?? DateTime.now(),
        dateModified = dateModified ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'patientName': patientName,
        'patientId': patientId,
        'audiologistName': audiologistName,
        'clinicName': clinicName,
        'dateCreated': dateCreated.toIso8601String(),
        'dateModified': dateModified.toIso8601String(),
        'notes': notes,
      };

  factory ProfileMetadata.fromJson(Map<String, dynamic> json) {
    return ProfileMetadata(
      patientName: json['patientName'] as String? ?? '',
      patientId: json['patientId'] as String? ?? '',
      audiologistName: json['audiologistName'] as String? ?? '',
      clinicName: json['clinicName'] as String? ?? '',
      dateCreated: json['dateCreated'] != null
          ? DateTime.parse(json['dateCreated'] as String)
          : null,
      dateModified: json['dateModified'] != null
          ? DateTime.parse(json['dateModified'] as String)
          : null,
      notes: json['notes'] as String? ?? '',
    );
  }
}

/// Master volume and mute controls.
class MasterConfig {
  double volumeDb;
  bool mute;

  MasterConfig({this.volumeDb = 0.0, this.mute = false});

  Map<String, dynamic> toJson() => {
        'volumeDb': volumeDb,
        'mute': mute,
      };

  factory MasterConfig.fromJson(Map<String, dynamic> json) {
    return MasterConfig(
      volumeDb: (json['volumeDb'] as num?)?.toDouble() ?? 0.0,
      mute: json['mute'] as bool? ?? false,
    );
  }
}

/// Noise reduction configuration.
class NoiseReductionConfig {
  bool enabled;
  double strengthPercent;

  NoiseReductionConfig({this.enabled = true, this.strengthPercent = 50.0});

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'strengthPercent': strengthPercent,
      };

  factory NoiseReductionConfig.fromJson(Map<String, dynamic> json) {
    return NoiseReductionConfig(
      enabled: json['enabled'] as bool? ?? true,
      strengthPercent:
          (json['strengthPercent'] as num?)?.toDouble() ?? 50.0,
    );
  }
}

/// High-frequency emphasis configuration.
class HighFreqEmphasisConfig {
  bool enabled;
  double startFreqHz;
  double maxEmphasisDb;
  double slopeDbPerOctave;

  HighFreqEmphasisConfig({
    this.enabled = true,
    this.startFreqHz = 1500.0,
    this.maxEmphasisDb = 12.0,
    this.slopeDbPerOctave = 3.0,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'startFreqHz': startFreqHz,
        'maxEmphasisDb': maxEmphasisDb,
        'slopeDbPerOctave': slopeDbPerOctave,
      };

  factory HighFreqEmphasisConfig.fromJson(Map<String, dynamic> json) {
    return HighFreqEmphasisConfig(
      enabled: json['enabled'] as bool? ?? true,
      startFreqHz:
          (json['startFreqHz'] as num?)?.toDouble() ?? 1500.0,
      maxEmphasisDb:
          (json['maxEmphasisDb'] as num?)?.toDouble() ?? 12.0,
      slopeDbPerOctave:
          (json['slopeDbPerOctave'] as num?)?.toDouble() ?? 3.0,
    );
  }
}

/// Complete hearing aid profile stored as `.haprofile` JSON.
///
/// Contains patient audiogram, 12-channel WDRC configuration,
/// master controls, noise reduction, and HF emphasis settings.
class HearingAidProfile {
  static const String currentVersion = '1.0';
  static const String fileExtension = '.haprofile';
  static const int numChannels = 12;

  final String version;
  ProfileMetadata metadata;
  PatientAudiogram audiogram;
  List<ChannelConfig> channels;
  MasterConfig master;
  NoiseReductionConfig noiseReduction;
  HighFreqEmphasisConfig highFreqEmphasis;

  HearingAidProfile({
    this.version = currentVersion,
    ProfileMetadata? metadata,
    PatientAudiogram? audiogram,
    List<ChannelConfig>? channels,
    MasterConfig? master,
    NoiseReductionConfig? noiseReduction,
    HighFreqEmphasisConfig? highFreqEmphasis,
  })  : metadata = metadata ?? ProfileMetadata(),
        audiogram = audiogram ?? PatientAudiogram(),
        channels = channels ?? ChannelConfig.createDefaults(),
        master = master ?? MasterConfig(),
        noiseReduction = noiseReduction ?? NoiseReductionConfig(),
        highFreqEmphasis = highFreqEmphasis ?? HighFreqEmphasisConfig();

  /// Serialize all 12 channels to firmware binary (for 'W' command payload).
  /// Returns 288 bytes (12 x 24).
  Uint8List channelsToFirmwareBinary() {
    final buffer = BytesBuilder();
    for (final ch in channels) {
      buffer.add(ch.toBytes());
    }
    return buffer.toBytes();
  }

  /// Serialize global config to firmware binary (for 'G' command payload).
  /// Returns 20 bytes matching global_config_wire_t.
  Uint8List globalToFirmwareBinary() {
    final data = ByteData(20);
    data.setFloat32(0, master.volumeDb, Endian.little);
    data.setUint8(4, master.mute ? 1 : 0);
    data.setUint8(5, noiseReduction.enabled ? 1 : 0);
    data.setFloat32(6, noiseReduction.strengthPercent / 100.0, Endian.little);
    data.setUint8(10, highFreqEmphasis.enabled ? 1 : 0);
    data.setFloat32(11, highFreqEmphasis.startFreqHz, Endian.little);
    data.setFloat32(15, highFreqEmphasis.maxEmphasisDb, Endian.little);
    data.setUint8(19, 0); // padding
    return data.buffer.asUint8List();
  }

  /// Serialize to JSON string for .haprofile file.
  String toJsonString() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'metadata': metadata.toJson(),
        'audiogram': audiogram.toJson(),
        'channels': channels.map((c) => c.toJson()).toList(),
        'master': master.toJson(),
        'noiseReduction': noiseReduction.toJson(),
        'highFreqEmphasis': highFreqEmphasis.toJson(),
      };

  factory HearingAidProfile.fromJson(Map<String, dynamic> json) {
    final channelList = (json['channels'] as List<dynamic>?)
            ?.map((c) => ChannelConfig.fromJson(c as Map<String, dynamic>))
            .toList() ??
        ChannelConfig.createDefaults();

    return HearingAidProfile(
      version: json['version'] as String? ?? currentVersion,
      metadata: json['metadata'] != null
          ? ProfileMetadata.fromJson(json['metadata'] as Map<String, dynamic>)
          : null,
      audiogram: json['audiogram'] != null
          ? PatientAudiogram.fromJson(
              json['audiogram'] as Map<String, dynamic>)
          : null,
      channels: channelList,
      master: json['master'] != null
          ? MasterConfig.fromJson(json['master'] as Map<String, dynamic>)
          : null,
      noiseReduction: json['noiseReduction'] != null
          ? NoiseReductionConfig.fromJson(
              json['noiseReduction'] as Map<String, dynamic>)
          : null,
      highFreqEmphasis: json['highFreqEmphasis'] != null
          ? HighFreqEmphasisConfig.fromJson(
              json['highFreqEmphasis'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Parse from .haprofile file content.
  factory HearingAidProfile.fromJsonString(String jsonString) {
    return HearingAidProfile.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }
}
