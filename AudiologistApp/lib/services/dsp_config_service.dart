import 'package:flutter/foundation.dart';
import 'package:fl_chart/fl_chart.dart';

import '../models/dsp_preset.dart';

/// Service for managing DSP configuration parameters
/// 
/// This service manages all DSP settings and communicates with
/// the hearing aid device to upload/download configurations.
class DspConfigService extends ChangeNotifier {
  
  // ============================================================
  // Master Controls
  // ============================================================
  double _masterVolume = -20.0;  // dB
  bool _isMuted = false;

  double get masterVolume => _masterVolume;
  bool get isMuted => _isMuted;

  void setMasterVolume(double value) {
    _masterVolume = value;
    _updateFrequencyResponse();
    notifyListeners();
  }

  void setMuted(bool value) {
    _isMuted = value;
    notifyListeners();
  }

  // ============================================================
  // Equalizer / Frequency Shaping
  // ============================================================
  double _eqLow = 0.0;      // 250 Hz
  double _eqLowMid = 0.0;   // 500 Hz
  double _eqMid = 0.0;      // 1 kHz
  double _eqHighMid = 0.0;  // 2 kHz
  double _eqHigh = 0.0;     // 4 kHz

  double get eqLow => _eqLow;
  double get eqLowMid => _eqLowMid;
  double get eqMid => _eqMid;
  double get eqHighMid => _eqHighMid;
  double get eqHigh => _eqHigh;

  void setEqLow(double value) {
    _eqLow = value;
    _updateFrequencyResponse();
    notifyListeners();
  }

  void setEqLowMid(double value) {
    _eqLowMid = value;
    _updateFrequencyResponse();
    notifyListeners();
  }

  void setEqMid(double value) {
    _eqMid = value;
    _updateFrequencyResponse();
    notifyListeners();
  }

  void setEqHighMid(double value) {
    _eqHighMid = value;
    _updateFrequencyResponse();
    notifyListeners();
  }

  void setEqHigh(double value) {
    _eqHigh = value;
    _updateFrequencyResponse();
    notifyListeners();
  }

  // ============================================================
  // Dynamic Range Compression (WDRC)
  // ============================================================
  double _compressionThreshold = -30.0;  // dB
  double _compressionRatio = 2.0;        // :1
  double _compressionAttack = 5.0;       // ms
  double _compressionRelease = 100.0;    // ms

  double get compressionThreshold => _compressionThreshold;
  double get compressionRatio => _compressionRatio;
  double get compressionAttack => _compressionAttack;
  double get compressionRelease => _compressionRelease;

  void setCompressionThreshold(double value) {
    _compressionThreshold = value;
    notifyListeners();
  }

  void setCompressionRatio(double value) {
    _compressionRatio = value;
    notifyListeners();
  }

  void setCompressionAttack(double value) {
    _compressionAttack = value;
    notifyListeners();
  }

  void setCompressionRelease(double value) {
    _compressionRelease = value;
    notifyListeners();
  }

  // ============================================================
  // Noise Reduction
  // ============================================================
  bool _noiseReductionEnabled = true;
  double _noiseReductionStrength = 50.0;  // %

  bool get noiseReductionEnabled => _noiseReductionEnabled;
  double get noiseReductionStrength => _noiseReductionStrength;

  void setNoiseReductionEnabled(bool value) {
    _noiseReductionEnabled = value;
    notifyListeners();
  }

  void setNoiseReductionStrength(double value) {
    _noiseReductionStrength = value;
    notifyListeners();
  }

  // ============================================================
  // Feedback Cancellation
  // ============================================================
  bool _feedbackCancellationEnabled = true;
  double _feedbackAdaptationRate = 50.0;  // %

  bool get feedbackCancellationEnabled => _feedbackCancellationEnabled;
  double get feedbackAdaptationRate => _feedbackAdaptationRate;

  void setFeedbackCancellationEnabled(bool value) {
    _feedbackCancellationEnabled = value;
    notifyListeners();
  }

  void setFeedbackAdaptationRate(double value) {
    _feedbackAdaptationRate = value;
    notifyListeners();
  }

  // ============================================================
  // Frequency Response Visualization
  // ============================================================
  List<FlSpot> _frequencyResponseData = [];
  
  List<FlSpot> get frequencyResponseData => _frequencyResponseData;

  void _updateFrequencyResponse() {
    // Calculate frequency response based on EQ settings
    // X-axis: 0-6 representing log scale from 125Hz to 8kHz
    // Y-axis: gain in dB
    _frequencyResponseData = [
      FlSpot(0, _eqLow * 0.5),        // 125 Hz (interpolated)
      FlSpot(1, _eqLow),               // 250 Hz
      FlSpot(2, _eqLowMid),            // 500 Hz
      FlSpot(3, _eqMid),               // 1 kHz
      FlSpot(4, _eqHighMid),           // 2 kHz
      FlSpot(5, _eqHigh),              // 4 kHz
      FlSpot(6, _eqHigh * 0.5),        // 8 kHz (interpolated)
    ];
  }

  // ============================================================
  // Level Metering (real-time from device)
  // ============================================================
  double _inputLevel = -60.0;
  double _outputLevel = -60.0;
  double _inputPeakLevel = -60.0;
  double _outputPeakLevel = -60.0;

  double get inputLevel => _inputLevel;
  double get outputLevel => _outputLevel;
  double get inputPeakLevel => _inputPeakLevel;
  double get outputPeakLevel => _outputPeakLevel;

  void updateLevels(double input, double output) {
    _inputLevel = input;
    _outputLevel = output;
    if (input > _inputPeakLevel) _inputPeakLevel = input;
    if (output > _outputPeakLevel) _outputPeakLevel = output;
    notifyListeners();
  }

  void resetPeakLevels() {
    _inputPeakLevel = -60.0;
    _outputPeakLevel = -60.0;
    notifyListeners();
  }

  // ============================================================
  // Test Signal Generation
  // ============================================================
  void playTestTone(int frequencyHz) {
    // TODO: Send command to device to play test tone
    debugPrint('Playing test tone: $frequencyHz Hz');
  }

  void playSweep() {
    // TODO: Send command to device to play frequency sweep
    debugPrint('Playing frequency sweep');
  }

  void playPinkNoise() {
    // TODO: Send command to device to play pink noise
    debugPrint('Playing pink noise');
  }

  // ============================================================
  // Device Communication
  // ============================================================
  Future<void> uploadToDevice() async {
    // TODO: Serialize all parameters and send to device via BLE
    // Format: Define a binary protocol or use JSON
    
    final config = _serializeConfig();
    debugPrint('Uploading config to device: ${config.length} bytes');
    
    // await deviceConnectionService.sendData(config);
  }

  Future<void> readFromDevice() async {
    // TODO: Read current configuration from device
    // final data = await deviceConnectionService.readData();
    // _deserializeConfig(data);
    
    debugPrint('Reading config from device');
    notifyListeners();
  }

  List<int> _serializeConfig() {
    // TODO: Implement proper serialization
    // This is a placeholder structure
    return [];
  }

  void _deserializeConfig(List<int> data) {
    // TODO: Implement proper deserialization
  }

  // ============================================================
  // Preset Management
  // ============================================================
  final List<DspPreset> _presets = [];
  
  List<DspPreset> get presets => List.unmodifiable(_presets);

  void saveCurrentAsPreset(String name, String notes) {
    final preset = DspPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      notes: notes,
      createdAt: DateTime.now(),
      masterVolume: _masterVolume,
      eqLow: _eqLow,
      eqLowMid: _eqLowMid,
      eqMid: _eqMid,
      eqHighMid: _eqHighMid,
      eqHigh: _eqHigh,
      compressionThreshold: _compressionThreshold,
      compressionRatio: _compressionRatio,
      compressionAttack: _compressionAttack,
      compressionRelease: _compressionRelease,
      noiseReductionEnabled: _noiseReductionEnabled,
      noiseReductionStrength: _noiseReductionStrength,
      feedbackCancellationEnabled: _feedbackCancellationEnabled,
      feedbackAdaptationRate: _feedbackAdaptationRate,
    );
    
    _presets.add(preset);
    // TODO: Persist to local storage
    notifyListeners();
  }

  void loadPreset(DspPreset preset) {
    _masterVolume = preset.masterVolume;
    _eqLow = preset.eqLow;
    _eqLowMid = preset.eqLowMid;
    _eqMid = preset.eqMid;
    _eqHighMid = preset.eqHighMid;
    _eqHigh = preset.eqHigh;
    _compressionThreshold = preset.compressionThreshold;
    _compressionRatio = preset.compressionRatio;
    _compressionAttack = preset.compressionAttack;
    _compressionRelease = preset.compressionRelease;
    _noiseReductionEnabled = preset.noiseReductionEnabled;
    _noiseReductionStrength = preset.noiseReductionStrength;
    _feedbackCancellationEnabled = preset.feedbackCancellationEnabled;
    _feedbackAdaptationRate = preset.feedbackAdaptationRate;
    
    _updateFrequencyResponse();
    notifyListeners();
  }

  void deletePreset(DspPreset preset) {
    _presets.removeWhere((p) => p.id == preset.id);
    // TODO: Remove from local storage
    notifyListeners();
  }

  void loadBuiltInPreset(String presetType) {
    // TODO: Define built-in presets for common hearing loss profiles
    switch (presetType) {
      case 'mild':
        _eqLow = 5;
        _eqLowMid = 5;
        _eqMid = 10;
        _eqHighMid = 10;
        _eqHigh = 15;
        _compressionRatio = 1.5;
        break;
      case 'moderate':
        _eqLow = 10;
        _eqLowMid = 15;
        _eqMid = 20;
        _eqHighMid = 20;
        _eqHigh = 25;
        _compressionRatio = 2.0;
        break;
      case 'severe':
        _eqLow = 20;
        _eqLowMid = 25;
        _eqMid = 30;
        _eqHighMid = 30;
        _eqHigh = 35;
        _compressionRatio = 3.0;
        break;
      case 'high_freq':
        _eqLow = 0;
        _eqLowMid = 5;
        _eqMid = 10;
        _eqHighMid = 20;
        _eqHigh = 25;
        break;
      case 'speech':
        _eqLow = -5;
        _eqLowMid = 0;
        _eqMid = 10;
        _eqHighMid = 15;
        _eqHigh = 10;
        _noiseReductionStrength = 70;
        break;
      case 'music':
        _eqLow = 5;
        _eqLowMid = 0;
        _eqMid = 0;
        _eqHighMid = 0;
        _eqHigh = 5;
        _compressionRatio = 1.2;
        _noiseReductionStrength = 20;
        break;
    }
    
    _updateFrequencyResponse();
    notifyListeners();
  }

  Future<void> importPreset() async {
    // TODO: Implement file picker to import preset JSON
    debugPrint('Import preset');
  }

  Future<void> exportPreset(DspPreset preset) async {
    // TODO: Implement file export
    debugPrint('Export preset: ${preset.name}');
  }

  // ============================================================
  // Reset
  // ============================================================
  void resetToDefaults() {
    _masterVolume = -20.0;
    _isMuted = false;
    _eqLow = 0.0;
    _eqLowMid = 0.0;
    _eqMid = 0.0;
    _eqHighMid = 0.0;
    _eqHigh = 0.0;
    _compressionThreshold = -30.0;
    _compressionRatio = 2.0;
    _compressionAttack = 5.0;
    _compressionRelease = 100.0;
    _noiseReductionEnabled = true;
    _noiseReductionStrength = 50.0;
    _feedbackCancellationEnabled = true;
    _feedbackAdaptationRate = 50.0;
    
    _updateFrequencyResponse();
    notifyListeners();
  }
}
