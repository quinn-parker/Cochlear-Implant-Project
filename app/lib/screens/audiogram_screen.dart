import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../models/audiogram.dart';
import '../services/dsp_config_service.dart';

/// Audiogram entry screen with interactive chart.
///
/// Allows entering hearing thresholds at standard frequencies for left/right ear,
/// air/bone conduction, and running auto-fit prescription.
class AudiogramScreen extends StatefulWidget {
  const AudiogramScreen({super.key});

  @override
  State<AudiogramScreen> createState() => _AudiogramScreenState();
}

class _AudiogramScreenState extends State<AudiogramScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedType = 'air'; // 'air' or 'bone'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DspConfigService>(
      builder: (context, dspService, _) {
        return Column(
          children: [
            // Ear selection tabs
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Right Ear'),
                Tab(text: 'Left Ear'),
              ],
              labelColor: Theme.of(context).colorScheme.primary,
            ),

            // Air/Bone toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'air', label: Text('Air Conduction')),
                  ButtonSegment(value: 'bone', label: Text('Bone Conduction')),
                ],
                selected: {_selectedType},
                onSelectionChanged: (v) =>
                    setState(() => _selectedType = v.first),
              ),
            ),

            // Audiogram chart
            Expanded(
              flex: 3,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildAudiogramChart(dspService, 'right'),
                  _buildAudiogramChart(dspService, 'left'),
                ],
              ),
            ),

            // Threshold entry controls
            Expanded(
              flex: 2,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildThresholdControls(dspService, 'right'),
                  _buildThresholdControls(dspService, 'left'),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _runAutoFit(dspService),
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Auto-Fit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _clearAudiogram(dspService),
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAudiogramChart(DspConfigService dspService, String ear) {
    final earData = ear == 'left'
        ? dspService.audiogram.left
        : dspService.audiogram.right;
    final airData = earData.airConduction;
    final boneData = earData.boneConduction;

    // Build spots for air conduction
    final airSpots = <FlSpot>[];
    final boneSpots = <FlSpot>[];

    for (final freq in AudiogramData.standardFrequencies) {
      final x = _freqToX(freq.toDouble());
      if (airData[freq] != null) {
        airSpots.add(FlSpot(x, airData[freq]!));
      }
      if (boneData[freq] != null) {
        boneSpots.add(FlSpot(x, boneData[freq]!));
      }
    }

    final isRight = ear == 'right';
    final airColor = isRight ? Colors.red : Colors.blue;
    final boneColor = isRight ? Colors.red.shade300 : Colors.blue.shade300;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: LineChart(
        LineChartData(
          minX: _freqToX(125),
          maxX: _freqToX(10000),
          minY: -10,
          maxY: 120,
          // Inverted Y axis (standard audiogram: better hearing at top)
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            drawVerticalLine: true,
            drawHorizontalLine: true,
            horizontalInterval: 10,
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 0.5,
            ),
            getDrawingHorizontalLine: (value) => FlLine(
              color: value == 25
                  ? Colors.green.shade300
                  : Colors.grey.shade300,
              strokeWidth: value == 25 ? 1.5 : 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: AxisTitles(
              axisNameWidget: Text(
                '${ear == "right" ? "Right" : "Left"} Ear Audiogram',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final freq = _xToFreq(value).round();
                  if (AudiogramData.standardFrequencies.contains(freq)) {
                    return Text(
                      freq >= 1000 ? '${freq ~/ 1000}k' : '$freq',
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: const AxisTitles(
              axisNameWidget: Text('Frequency (Hz)'),
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              axisNameWidget: const Text('dB HL'),
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 20,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            if (airSpots.isNotEmpty)
              LineChartBarData(
                spots: airSpots,
                color: airColor,
                barWidth: 2,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      _audiogramDotPainter(isRight, true, airColor),
                ),
              ),
            if (boneSpots.isNotEmpty)
              LineChartBarData(
                spots: boneSpots,
                color: boneColor,
                barWidth: 2,
                dashArray: [5, 3],
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      _audiogramDotPainter(isRight, false, boneColor),
                ),
              ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final freq = _xToFreq(spot.x).round();
                return LineTooltipItem(
                  '$freq Hz: ${spot.y.toInt()} dB HL',
                  TextStyle(color: spot.bar.color, fontWeight: FontWeight.bold),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  FlDotPainter _audiogramDotPainter(bool isRight, bool isAir, Color color) {
    // Standard audiogram symbols:
    // Right air: O, Left air: X, Right bone: <, Left bone: >
    // We approximate with circles/squares
    if (isAir) {
      return FlDotCirclePainter(
        radius: 6,
        color: isRight ? Colors.transparent : Colors.transparent,
        strokeColor: color,
        strokeWidth: 2,
      );
    }
    return FlDotSquarePainter(
      size: 10,
      color: Colors.transparent,
      strokeColor: color,
      strokeWidth: 2,
    );
  }

  Widget _buildThresholdControls(DspConfigService dspService, String ear) {
    final earData = ear == 'left'
        ? dspService.audiogram.left
        : dspService.audiogram.right;
    final data =
        _selectedType == 'air' ? earData.airConduction : earData.boneConduction;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_selectedType == "air" ? "Air" : "Bone"} Conduction Thresholds (dB HL)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: AudiogramData.standardFrequencies.map((freq) {
              final value = data[freq];
              return SizedBox(
                width: 85,
                child: Column(
                  children: [
                    Text(
                      freq >= 1000 ? '${freq ~/ 1000}k Hz' : '$freq Hz',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                    SizedBox(
                      width: 70,
                      child: TextFormField(
                        key: ValueKey('${ear}_${_selectedType}_$freq'),
                        initialValue: value?.toInt().toString() ?? '',
                        keyboardType: const TextInputType.numberWithOptions(
                            signed: true),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 8),
                          hintText: '--',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        onChanged: (text) {
                          final val = double.tryParse(text);
                          dspService.setAudiogramThreshold(
                              ear, _selectedType, freq, val);
                        },
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          if (earData.pta != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'PTA: ${earData.pta!.toStringAsFixed(1)} dB HL '
                '(${AudiogramData.classifyLoss(earData.pta)})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _runAutoFit(DspConfigService dspService) {
    final ear = _tabController.index == 0 ? 'right' : 'left';
    dspService.runAutoFit(ear: ear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Auto-fit applied for ${ear == "right" ? "right" : "left"} ear'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearAudiogram(DspConfigService dspService) {
    final ear = _tabController.index == 0 ? 'right' : 'left';
    if (ear == 'right') {
      dspService.updateAudiogram(
        dspService.audiogram.copyWith(right: AudiogramData()),
      );
    } else {
      dspService.updateAudiogram(
        dspService.audiogram.copyWith(left: AudiogramData()),
      );
    }
  }

  // Log-frequency mapping for audiogram X axis
  double _freqToX(double freq) => log(freq) / ln10;
  double _xToFreq(double x) => pow(10, x).toDouble();
}
