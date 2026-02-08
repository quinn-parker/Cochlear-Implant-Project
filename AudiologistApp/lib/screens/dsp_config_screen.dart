import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/dsp_config_service.dart';
import '../services/device_connection_service.dart';
import '../widgets/parameter_slider.dart';

/// Main DSP parameter configuration screen
class DspConfigScreen extends StatelessWidget {
  const DspConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dspService = context.watch<DspConfigService>();
    final deviceService = context.watch<DeviceConnectionService>();

    if (!deviceService.isConnected) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Connect to a device to configure DSP parameters'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Master Volume
          _SectionCard(
            title: 'Master Controls',
            icon: Icons.volume_up,
            children: [
              ParameterSlider(
                label: 'Master Volume',
                value: dspService.masterVolume,
                min: -60,
                max: 0,
                unit: 'dB',
                onChanged: (v) => dspService.setMasterVolume(v),
              ),
              SwitchListTile(
                title: const Text('Mute Output'),
                value: dspService.isMuted,
                onChanged: (v) => dspService.setMuted(v),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Equalizer / Frequency Shaping
          _SectionCard(
            title: 'Frequency Shaping (EQ)',
            icon: Icons.equalizer,
            children: [
              ParameterSlider(
                label: 'Low Freq (250 Hz)',
                value: dspService.eqLow,
                min: -20,
                max: 20,
                unit: 'dB',
                onChanged: (v) => dspService.setEqLow(v),
              ),
              ParameterSlider(
                label: 'Low-Mid (500 Hz)',
                value: dspService.eqLowMid,
                min: -20,
                max: 20,
                unit: 'dB',
                onChanged: (v) => dspService.setEqLowMid(v),
              ),
              ParameterSlider(
                label: 'Mid (1 kHz)',
                value: dspService.eqMid,
                min: -20,
                max: 20,
                unit: 'dB',
                onChanged: (v) => dspService.setEqMid(v),
              ),
              ParameterSlider(
                label: 'High-Mid (2 kHz)',
                value: dspService.eqHighMid,
                min: -20,
                max: 20,
                unit: 'dB',
                onChanged: (v) => dspService.setEqHighMid(v),
              ),
              ParameterSlider(
                label: 'High (4 kHz)',
                value: dspService.eqHigh,
                min: -20,
                max: 20,
                unit: 'dB',
                onChanged: (v) => dspService.setEqHigh(v),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Dynamic Range Compression
          _SectionCard(
            title: 'Compression (WDRC)',
            icon: Icons.compress,
            children: [
              ParameterSlider(
                label: 'Threshold',
                value: dspService.compressionThreshold,
                min: -60,
                max: 0,
                unit: 'dB',
                onChanged: (v) => dspService.setCompressionThreshold(v),
              ),
              ParameterSlider(
                label: 'Ratio',
                value: dspService.compressionRatio,
                min: 1,
                max: 10,
                unit: ':1',
                onChanged: (v) => dspService.setCompressionRatio(v),
              ),
              ParameterSlider(
                label: 'Attack Time',
                value: dspService.compressionAttack,
                min: 1,
                max: 100,
                unit: 'ms',
                onChanged: (v) => dspService.setCompressionAttack(v),
              ),
              ParameterSlider(
                label: 'Release Time',
                value: dspService.compressionRelease,
                min: 10,
                max: 500,
                unit: 'ms',
                onChanged: (v) => dspService.setCompressionRelease(v),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Noise Reduction
          _SectionCard(
            title: 'Noise Reduction',
            icon: Icons.noise_aware,
            children: [
              SwitchListTile(
                title: const Text('Enable Noise Reduction'),
                value: dspService.noiseReductionEnabled,
                onChanged: (v) => dspService.setNoiseReductionEnabled(v),
              ),
              ParameterSlider(
                label: 'NR Strength',
                value: dspService.noiseReductionStrength,
                min: 0,
                max: 100,
                unit: '%',
                onChanged: dspService.noiseReductionEnabled
                  ? (v) => dspService.setNoiseReductionStrength(v)
                  : null,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Feedback Cancellation
          _SectionCard(
            title: 'Feedback Cancellation',
            icon: Icons.surround_sound,
            children: [
              SwitchListTile(
                title: const Text('Enable Feedback Cancellation'),
                value: dspService.feedbackCancellationEnabled,
                onChanged: (v) => dspService.setFeedbackCancellationEnabled(v),
              ),
              ParameterSlider(
                label: 'Adaptation Rate',
                value: dspService.feedbackAdaptationRate,
                min: 0,
                max: 100,
                unit: '%',
                onChanged: dspService.feedbackCancellationEnabled
                  ? (v) => dspService.setFeedbackAdaptationRate(v)
                  : null,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => dspService.uploadToDevice(),
                icon: const Icon(Icons.upload),
                label: const Text('Upload to Device'),
              ),
              OutlinedButton.icon(
                onPressed: () => dspService.readFromDevice(),
                icon: const Icon(Icons.download),
                label: const Text('Read from Device'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: () => dspService.resetToDefaults(),
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
          ),
        ],
      ),
    );
  }
}

/// Reusable card widget for grouping related parameters
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }
}
