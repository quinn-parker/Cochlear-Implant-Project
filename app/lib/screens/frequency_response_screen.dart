import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../models/audiogram.dart';
import '../services/dsp_config_service.dart';

/// Visualization screen showing I/O function and audiogram overlay.
class FrequencyResponseScreen extends StatefulWidget {
  const FrequencyResponseScreen({super.key});

  @override
  State<FrequencyResponseScreen> createState() =>
      _FrequencyResponseScreenState();
}

class _FrequencyResponseScreenState extends State<FrequencyResponseScreen> {
  int _selectedChannel = 4; // Default: 1000 Hz
  bool _showAudiogramOverlay = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<DspConfigService>(
      builder: (context, dspService, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // I/O Function for selected channel
              _buildSectionTitle('I/O Function'),
              _buildChannelSelector(dspService),
              _buildIoFunctionChart(dspService),
              const SizedBox(height: 16),

              // Gain curve with audiogram overlay
              Row(
                children: [
                  Expanded(child: _buildSectionTitle('Gain + Audiogram')),
                  Row(
                    children: [
                      const Text('Audiogram overlay',
                          style: TextStyle(fontSize: 12)),
                      Switch(
                        value: _showAudiogramOverlay,
                        onChanged: (v) =>
                            setState(() => _showAudiogramOverlay = v),
                      ),
                    ],
                  ),
                ],
              ),
              _buildGainWithAudiogramChart(dspService),
              const SizedBox(height: 16),

              // Noise reduction & HF emphasis global settings
              _buildGlobalSettings(dspService),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildChannelSelector(DspConfigService dspService) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: dspService.channels.length,
        itemBuilder: (context, index) {
          final ch = dspService.channels[index];
          final label = ch.centerFreqHz >= 1000
              ? '${(ch.centerFreqHz / 1000).toStringAsFixed(ch.centerFreqHz % 1000 == 0 ? 0 : 1)}k'
              : '${ch.centerFreqHz.toInt()}';
          final isSelected = index == _selectedChannel;
          return Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 11)),
              selected: isSelected,
              onSelected: (_) =>
                  setState(() => _selectedChannel = index),
              visualDensity: VisualDensity.compact,
            ),
          );
        },
      ),
    );
  }

  Widget _buildIoFunctionChart(DspConfigService dspService) {
    final ioData = dspService.computeIoFunction(_selectedChannel);
    final ch = dspService.channels[_selectedChannel];

    final spots =
        ioData.map((e) => FlSpot(e.key, e.value)).toList();

    // MPO line
    final mpoSpots = [
      FlSpot(-60, ch.mpoDbSpl - 94),
      FlSpot(10, ch.mpoDbSpl - 94),
    ];

    // Unity gain line (1:1)
    final unitySpots = [FlSpot(-60, -60), FlSpot(10, 10)];

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minX: -60,
          maxX: 10,
          minY: -60,
          maxY: 40,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            horizontalInterval: 10,
            verticalInterval: 10,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
            getDrawingVerticalLine: (v) =>
                FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            topTitles: AxisTitles(
              axisNameWidget: Text(
                'I/O: ${ch.centerFreqHz.toInt()} Hz (Ratio ${ch.ratio.toStringAsFixed(1)}:1)',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              sideTitles: const SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              axisNameWidget:
                  const Text('Input (dB)', style: TextStyle(fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 24,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget:
                  const Text('Output (dB)', style: TextStyle(fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 35,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            // Unity line
            LineChartBarData(
              spots: unitySpots,
              color: Colors.grey.shade400,
              barWidth: 1,
              dashArray: [4, 4],
              dotData: const FlDotData(show: false),
            ),
            // MPO ceiling
            LineChartBarData(
              spots: mpoSpots,
              color: Colors.red.shade300,
              barWidth: 1.5,
              dashArray: [6, 3],
              dotData: const FlDotData(show: false),
            ),
            // I/O curve
            LineChartBarData(
              spots: spots,
              color: Colors.blue,
              barWidth: 2.5,
              isCurved: true,
              curveSmoothness: 0.2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGainWithAudiogramChart(DspConfigService dspService) {
    final medCurve = dspService.computeGainCurve(65);

    final gainSpots = medCurve
        .map((e) => FlSpot(log(e.key) / ln10, e.value))
        .toList();

    // Audiogram overlay (right ear air conduction)
    final audioSpots = <FlSpot>[];
    if (_showAudiogramOverlay) {
      final airData = dspService.audiogram.right.airConduction;
      for (final entry in airData.entries) {
        if (entry.value != null) {
          audioSpots.add(FlSpot(
              log(entry.key.toDouble()) / ln10, entry.value!));
        }
      }
    }

    return SizedBox(
      height: 250,
      child: LineChart(
        LineChartData(
          minX: log(150) / ln10,
          maxX: log(9000) / ln10,
          minY: -10,
          maxY: 80,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            horizontalInterval: 10,
            getDrawingHorizontalLine: (v) =>
                FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
            getDrawingVerticalLine: (v) =>
                FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              axisNameWidget:
                  const Text('Frequency (Hz)', style: TextStyle(fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final freq = pow(10, value).round();
                  const labels = {
                    250: '250', 500: '500', 1000: '1k',
                    2000: '2k', 4000: '4k', 8000: '8k'
                  };
                  for (final entry in labels.entries) {
                    if ((log(entry.key) / ln10 - value).abs() < 0.05) {
                      return Text(entry.value,
                          style: const TextStyle(fontSize: 10));
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            leftTitles: AxisTitles(
              axisNameWidget:
                  const Text('dB', style: TextStyle(fontSize: 10)),
              sideTitles: SideTitles(
                showTitles: true,
                interval: 10,
                reservedSize: 30,
                getTitlesWidget: (v, _) => Text('${v.toInt()}',
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            // Gain curve
            LineChartBarData(
              spots: gainSpots,
              color: Colors.blue,
              barWidth: 2.5,
              isCurved: true,
              curveSmoothness: 0.3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withAlpha(30),
              ),
            ),
            // Audiogram overlay
            if (audioSpots.isNotEmpty)
              LineChartBarData(
                spots: audioSpots,
                color: Colors.red,
                barWidth: 2,
                dashArray: [5, 3],
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, p, bar, i) =>
                      FlDotCirclePainter(
                    radius: 5,
                    color: Colors.transparent,
                    strokeColor: Colors.red,
                    strokeWidth: 2,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSettings(DspConfigService dspService) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Global Settings',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Noise Reduction'),
              subtitle: Text(
                  'Strength: ${dspService.noiseReduction.strengthPercent.toStringAsFixed(0)}%'),
              value: dspService.noiseReduction.enabled,
              onChanged: (v) => dspService.setNoiseReductionEnabled(v),
              dense: true,
            ),
            if (dspService.noiseReduction.enabled)
              Slider(
                value: dspService.noiseReduction.strengthPercent,
                min: 0,
                max: 100,
                divisions: 20,
                label:
                    '${dspService.noiseReduction.strengthPercent.toStringAsFixed(0)}%',
                onChanged: (v) => dspService.setNoiseReductionStrength(v),
              ),
            SwitchListTile(
              title: const Text('High-Frequency Emphasis'),
              subtitle: Text(
                  'Max: ${dspService.highFreqEmphasis.maxEmphasisDb.toStringAsFixed(0)} dB'),
              value: dspService.highFreqEmphasis.enabled,
              onChanged: (v) => dspService.setHfEmphasisEnabled(v),
              dense: true,
            ),
            if (dspService.highFreqEmphasis.enabled)
              Slider(
                value: dspService.highFreqEmphasis.maxEmphasisDb,
                min: 0,
                max: 20,
                divisions: 20,
                label:
                    '${dspService.highFreqEmphasis.maxEmphasisDb.toStringAsFixed(0)} dB',
                onChanged: (v) => dspService.setHfEmphasisMaxDb(v),
              ),
          ],
        ),
      ),
    );
  }
}
