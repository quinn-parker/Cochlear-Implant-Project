import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

import '../models/hearing_aid_profile.dart';
import '../models/channel_config.dart';
import '../models/audiogram.dart';
import 'device_connection_service.dart';
import 'autofit_service.dart';

/// Central service managing the current hearing aid profile and device communication.
///
/// Replaces the old 5-band EQ model with 12-channel WDRC.
/// Handles profile persistence, auto-fit, and device upload/download.
class DspConfigService extends ChangeNotifier {
  final DeviceConnectionService _connectionService;
  HearingAidProfile _currentProfile = HearingAidProfile();

  /// Debounce timer for single-channel updates during slider drag.
  Timer? _debounceTimer;
  int? _pendingChannelIndex;

  DspConfigService(this._connectionService);

  // ====================================================================
  // Profile Access
  // ====================================================================

  HearingAidProfile get currentProfile => _currentProfile;
  List<ChannelConfig> get channels => _currentProfile.channels;
  MasterConfig get master => _currentProfile.master;
  NoiseReductionConfig get noiseReduction => _currentProfile.noiseReduction;
  HighFreqEmphasisConfig get highFreqEmphasis => _currentProfile.highFreqEmphasis;
  PatientAudiogram get audiogram => _currentProfile.audiogram;
  ProfileMetadata get metadata => _currentProfile.metadata;

  // ====================================================================
  // Channel Parameter Updates
  // ====================================================================

  void updateChannelGain(int index, double gainDb) {
    _currentProfile.channels[index].gainDb = gainDb;
    _debouncedSendChannel(index);
    notifyListeners();
  }

  void updateChannelThreshold(int index, double thresholdDb) {
    _currentProfile.channels[index].thresholdDb = thresholdDb;
    _debouncedSendChannel(index);
    notifyListeners();
  }

  void updateChannelRatio(int index, double ratio) {
    _currentProfile.channels[index].ratio = ratio;
    _debouncedSendChannel(index);
    notifyListeners();
  }

  void updateChannelAttack(int index, double attackMs) {
    _currentProfile.channels[index].attackMs = attackMs;
    _debouncedSendChannel(index);
    notifyListeners();
  }

  void updateChannelRelease(int index, double releaseMs) {
    _currentProfile.channels[index].releaseMs = releaseMs;
    _debouncedSendChannel(index);
    notifyListeners();
  }

  void updateChannelMpo(int index, double mpoDbSpl) {
    _currentProfile.channels[index].mpoDbSpl = mpoDbSpl;
    _debouncedSendChannel(index);
    notifyListeners();
  }

  // ====================================================================
  // Master & Global Updates
  // ====================================================================

  void setMasterVolume(double volumeDb) {
    _currentProfile.master.volumeDb = volumeDb;
    notifyListeners();
  }

  void setMuted(bool mute) {
    _currentProfile.master.mute = mute;
    notifyListeners();
  }

  void setNoiseReductionEnabled(bool enabled) {
    _currentProfile.noiseReduction.enabled = enabled;
    notifyListeners();
  }

  void setNoiseReductionStrength(double strength) {
    _currentProfile.noiseReduction.strengthPercent = strength;
    notifyListeners();
  }

  void setHfEmphasisEnabled(bool enabled) {
    _currentProfile.highFreqEmphasis.enabled = enabled;
    notifyListeners();
  }

  void setHfEmphasisMaxDb(double maxDb) {
    _currentProfile.highFreqEmphasis.maxEmphasisDb = maxDb;
    notifyListeners();
  }

  // ====================================================================
  // Audiogram & Auto-Fit
  // ====================================================================

  void updateAudiogram(PatientAudiogram audiogram) {
    _currentProfile.audiogram = audiogram;
    notifyListeners();
  }

  /// Set a single audiogram threshold value.
  void setAudiogramThreshold(
      String ear, String type, int freqHz, double? value) {
    final earData =
        ear == 'left' ? _currentProfile.audiogram.left : _currentProfile.audiogram.right;
    final map = type == 'air' ? earData.airConduction : earData.boneConduction;
    map[freqHz] = value;
    notifyListeners();
  }

  /// Run auto-fit prescription on the current audiogram.
  /// Replaces all 12 channel configs with prescribed values.
  void runAutoFit({String ear = 'right', bool bilateral = false}) {
    final earData =
        ear == 'left' ? _currentProfile.audiogram.left : _currentProfile.audiogram.right;
    _currentProfile.channels = AutofitService.prescribe(
      earData,
      isBilateral: bilateral,
    );
    notifyListeners();
  }

  // ====================================================================
  // Metadata
  // ====================================================================

  void updateMetadata({
    String? patientName,
    String? patientId,
    String? audiologistName,
    String? clinicName,
    String? notes,
  }) {
    if (patientName != null) _currentProfile.metadata.patientName = patientName;
    if (patientId != null) _currentProfile.metadata.patientId = patientId;
    if (audiologistName != null) {
      _currentProfile.metadata.audiologistName = audiologistName;
    }
    if (clinicName != null) _currentProfile.metadata.clinicName = clinicName;
    if (notes != null) _currentProfile.metadata.notes = notes;
    _currentProfile.metadata.dateModified = DateTime.now();
    notifyListeners();
  }

  // ====================================================================
  // Device Communication
  // ====================================================================

  /// Upload entire profile to connected device.
  Future<bool> uploadFullConfig() async {
    final protocol = _connectionService.protocol;
    if (protocol == null) return false;

    try {
      final chanOk = await protocol.writeFullConfig(_currentProfile.channels);
      if (!chanOk) return false;

      final globOk = await protocol.writeGlobalConfig(_currentProfile);
      return globOk;
    } catch (e) {
      debugPrint('Upload failed: $e');
      return false;
    }
  }

  /// Read current config from device and update local profile.
  Future<bool> readFromDevice() async {
    final protocol = _connectionService.protocol;
    if (protocol == null) return false;

    try {
      final channels = await protocol.readDeviceConfig();
      if (channels != null) {
        _currentProfile.channels = channels;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Read failed: $e');
      return false;
    }
  }

  /// Upload global config only (master, NR, HF emphasis).
  Future<bool> uploadGlobalConfig() async {
    final protocol = _connectionService.protocol;
    if (protocol == null) return false;

    try {
      return await protocol.writeGlobalConfig(_currentProfile);
    } catch (e) {
      debugPrint('Global upload failed: $e');
      return false;
    }
  }

  /// Debounced single-channel send for real-time slider feedback.
  void _debouncedSendChannel(int index) {
    _pendingChannelIndex = index;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _sendSingleChannel(_pendingChannelIndex!);
    });
  }

  Future<void> _sendSingleChannel(int index) async {
    final protocol = _connectionService.protocol;
    if (protocol == null) return;
    try {
      await protocol.writeSingleChannel(_currentProfile.channels[index]);
    } catch (e) {
      debugPrint('Single channel send failed: $e');
    }
  }

  // ====================================================================
  // Frequency Response Computation (for visualization)
  // ====================================================================

  /// Compute effective gain at each channel frequency for a given input level.
  /// Returns list of (freqHz, gainDb) pairs.
  List<MapEntry<double, double>> computeGainCurve(double inputLevelDb) {
    return _currentProfile.channels.map((ch) {
      final gain = ch.computeGainAtInput(inputLevelDb);
      return MapEntry(ch.centerFreqHz, gain);
    }).toList();
  }

  /// Compute I/O function for a specific channel.
  /// Returns list of (inputDb, outputDb) pairs.
  List<MapEntry<double, double>> computeIoFunction(int channelIndex) {
    final ch = _currentProfile.channels[channelIndex];
    final points = <MapEntry<double, double>>[];
    for (double input = -60; input <= 10; input += 2) {
      final output = ch.computeOutputAtInput(input);
      points.add(MapEntry(input, output));
    }
    return points;
  }

  // ====================================================================
  // Profile File Management
  // ====================================================================

  /// Save current profile to a .haprofile file.
  Future<String?> saveProfile() async {
    _currentProfile.metadata.dateModified = DateTime.now();
    final dir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${dir.path}/haprofiles');
    if (!await profileDir.exists()) {
      await profileDir.create(recursive: true);
    }

    final safeName = _currentProfile.metadata.patientName.isNotEmpty
        ? _currentProfile.metadata.patientName
            .replaceAll(RegExp(r'[^\w\s-]'), '')
            .replaceAll(RegExp(r'\s+'), '_')
        : 'profile_${DateTime.now().millisecondsSinceEpoch}';
    final path = '${profileDir.path}/$safeName.haprofile';
    final file = File(path);
    await file.writeAsString(_currentProfile.toJsonString());
    return path;
  }

  /// Load a profile from a .haprofile file.
  Future<bool> loadProfile(String path) async {
    try {
      final file = File(path);
      final content = await file.readAsString();
      _currentProfile = HearingAidProfile.fromJsonString(content);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to load profile: $e');
      return false;
    }
  }

  /// List saved profiles.
  Future<List<String>> listSavedProfiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final profileDir = Directory('${dir.path}/haprofiles');
    if (!await profileDir.exists()) return [];

    return profileDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.haprofile'))
        .map((f) => f.path)
        .toList();
  }

  /// Import profile via file picker.
  Future<bool> importProfile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['haprofile', 'json'],
    );
    if (result == null || result.files.isEmpty) return false;
    return loadProfile(result.files.single.path!);
  }

  /// Export current profile via file picker.
  Future<bool> exportProfile() async {
    final bytes = utf8.encode(_currentProfile.toJsonString());
    final safeName = _currentProfile.metadata.patientName.isNotEmpty
        ? _currentProfile.metadata.patientName
        : 'hearing_aid_profile';
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Profile',
      fileName: '$safeName.haprofile',
      bytes: Uint8List.fromList(bytes),
    );
    return result != null;
  }

  // ====================================================================
  // Built-in Presets
  // ====================================================================

  void loadBuiltInPreset(String type) {
    switch (type) {
      case 'mild':
        _currentProfile.channels = AutofitService.mildLossPreset();
        break;
      case 'moderate':
        _currentProfile.channels = AutofitService.moderateLossPreset();
        break;
      case 'severe':
        _currentProfile.channels = AutofitService.severeLossPreset();
        break;
      case 'high_freq':
        _currentProfile.channels = AutofitService.highFreqLossPreset();
        break;
      default:
        return;
    }
    notifyListeners();
  }

  /// Reset to factory defaults.
  void resetToDefaults() {
    _currentProfile = HearingAidProfile();
    notifyListeners();
  }

  /// Load a full profile object (e.g., from profile management screen).
  void setProfile(HearingAidProfile profile) {
    _currentProfile = profile;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
