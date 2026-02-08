import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../services/dsp_config_service.dart';
import '../services/device_connection_service.dart';

/// Frequency response visualization screen
class FrequencyResponseScreen extends StatelessWidget {
  const FrequencyResponseScreen({super.key});

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
            Text('Connect to a device to view frequency response'),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Chart title
          Text(
            'Frequency Response Curve',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Showing combined effect of EQ and compression settings',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 24),
          
          // Frequency response chart
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _FrequencyResponseChart(
                  responseData: dspService.frequencyResponseData,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Input/Output level meters
          Row(
            children: [
              Expanded(
                child: _LevelMeter(
                  label: 'Input Level',
                  level: dspService.inputLevel,
                  peakLevel: dspService.inputPeakLevel,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _LevelMeter(
                  label: 'Output Level',
                  level: dspService.outputLevel,
                  peakLevel: dspService.outputPeakLevel,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Test controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Test Signals',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: () => dspService.playTestTone(1000),
                        child: const Text('1 kHz Tone'),
                      ),
                      ElevatedButton(
                        onPressed: () => dspService.playTestTone(250),
                        child: const Text('250 Hz Tone'),
                      ),
                      ElevatedButton(
                        onPressed: () => dspService.playTestTone(4000),
                        child: const Text('4 kHz Tone'),
                      ),
                      OutlinedButton(
                        onPressed: () => dspService.playSweep(),
                        child: const Text('Frequency Sweep'),
                      ),
                      OutlinedButton(
                        onPressed: () => dspService.playPinkNoise(),
                        child: const Text('Pink Noise'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frequency response chart widget
class _FrequencyResponseChart extends StatelessWidget {
  final List<FlSpot> responseData;

  const _FrequencyResponseChart({required this.responseData});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: 10,
          verticalInterval: 1,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            axisNameWidget: const Text('Gain (dB)'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: 10,
            ),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Frequency (Hz)'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) {
                // Log scale labels
                const labels = {
                  0: '125',
                  1: '250',
                  2: '500',
                  3: '1k',
                  4: '2k',
                  5: '4k',
                  6: '8k',
                };
                return Text(labels[value.toInt()] ?? '');
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: true),
        minX: 0,
        maxX: 6,
        minY: -30,
        maxY: 30,
        lineBarsData: [
          LineChartBarData(
            spots: responseData.isEmpty ? _defaultResponseData() : responseData,
            isCurved: true,
            color: colorScheme.primary,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: colorScheme.primary.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  List<FlSpot> _defaultResponseData() {
    // Flat response as default
    return const [
      FlSpot(0, 0),
      FlSpot(1, 0),
      FlSpot(2, 0),
      FlSpot(3, 0),
      FlSpot(4, 0),
      FlSpot(5, 0),
      FlSpot(6, 0),
    ];
  }
}

/// Audio level meter widget
class _LevelMeter extends StatelessWidget {
  final String label;
  final double level;      // Current level in dB
  final double peakLevel;  // Peak hold level in dB

  const _LevelMeter({
    required this.label,
    required this.level,
    required this.peakLevel,
  });

  @override
  Widget build(BuildContext context) {
    // Normalize to 0-1 range (-60 dB to 0 dB)
    final normalizedLevel = ((level + 60) / 60).clamp(0.0, 1.0);
    final normalizedPeak = ((peakLevel + 60) / 60).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Stack(
              children: [
                // Background
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                // Level bar
                FractionallySizedBox(
                  widthFactor: normalizedLevel,
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.green,
                          Colors.yellow,
                          Colors.orange,
                          Colors.red,
                        ],
                        stops: const [0.0, 0.6, 0.8, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                // Peak indicator
                Positioned(
                  left: normalizedPeak * MediaQuery.of(context).size.width * 0.35,
                  child: Container(
                    width: 2,
                    height: 24,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${level.toStringAsFixed(1)} dB (Peak: ${peakLevel.toStringAsFixed(1)} dB)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
