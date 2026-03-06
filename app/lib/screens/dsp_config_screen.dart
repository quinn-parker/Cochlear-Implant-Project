import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../services/dsp_config_service.dart';
import '../services/device_connection_service.dart';

/// DSP configuration screen with 12-channel controls and frequency response graph.
class DspConfigScreen extends StatefulWidget {
  const DspConfigScreen({super.key});

  @override
  State<DspConfigScreen> createState() => _DspConfigScreenState();
}

class _DspConfigScreenState extends State<DspConfigScreen> {
  int? _expandedChannel;

  @override
  Widget build(BuildContext context) {
    return Consumer2<DspConfigService, DeviceConnectionService>(
      builder: (context, dspService, connService, _) {
        return Column(
          children: [
            _buildFrequencyResponseGraph(dspService),
            _buildMasterControls(dspService),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: dspService.channels.length,
                itemBuilder: (context, index) =>
                    _buildChannelCard(dspService, index),
              ),
            ),
            _buildActionBar(dspService, connService),
          ],
        );
      },
    );
  }

  Widget _buildFrequencyResponseGraph(DspConfigService dspService) {
    final softCurve = dspService.computeGainCurve(50);
    final medCurve = dspService.computeGainCurve(65);
    final loudCurve = dspService.computeGainCurve(80);

    FlSpot toSpot(MapEntry<double, double> e) =>
        FlSpot(log(e.key) / ln10, e.value);

    return SizedBox(
      height: 200,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
        child: LineChart(
          LineChartData(
            minX: log(150) / ln10,
            maxX: log(9000) / ln10,
            minY: -20,
            maxY: 60,
            clipData: const FlClipData.all(),
            gridData: FlGridData(
              drawVerticalLine: true,
              horizontalInterval: 10,
              getDrawingVerticalLine: (value) =>
                  FlLine(color: Colors.grey.shade300, strokeWidth: 0.5),
              getDrawingHorizontalLine: (value) => FlLine(
                color:
                    value == 0 ? Colors.grey.shade600 : Colors.grey.shade300,
                strokeWidth: value == 0 ? 1.0 : 0.5,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                axisNameWidget: Text('Frequency Response',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final freq = pow(10, value).round();
                    const labels = {
                      200: '200', 500: '500', 1000: '1k',
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
                    const Text('Gain (dB)', style: TextStyle(fontSize: 10)),
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  interval: 10,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}',
                      style: const TextStyle(fontSize: 10)),
                ),
              ),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
            ),
            lineBarsData: [
              _curveLine(
                  softCurve.map(toSpot).toList(), Colors.green.shade400),
              _curveLine(medCurve.map(toSpot).toList(), Colors.blue),
              _curveLine(
                  loudCurve.map(toSpot).toList(), Colors.orange.shade700),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((spot) {
                  final freq = pow(10, spot.x).round();
                  return LineTooltipItem(
                    '$freq Hz: ${spot.y.toStringAsFixed(1)} dB',
                    TextStyle(color: spot.bar.color, fontSize: 11),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  LineChartBarData _curveLine(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      color: color,
      barWidth: 2,
      isCurved: true,
      curveSmoothness: 0.3,
      dotData: const FlDotData(show: false),
    );
  }

  Widget _buildMasterControls(DspConfigService dspService) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            IconButton(
              icon: Icon(dspService.master.mute
                  ? Icons.volume_off
                  : Icons.volume_up),
              onPressed: () =>
                  dspService.setMuted(!dspService.master.mute),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Master Volume',
                      style: TextStyle(fontSize: 12)),
                  Slider(
                    value: dspService.master.volumeDb,
                    min: -60,
                    max: 0,
                    divisions: 60,
                    label:
                        '${dspService.master.volumeDb.toStringAsFixed(0)} dB',
                    onChanged: (v) => dspService.setMasterVolume(v),
                  ),
                ],
              ),
            ),
            Text('${dspService.master.volumeDb.toStringAsFixed(0)} dB',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelCard(DspConfigService dspService, int index) {
    final ch = dspService.channels[index];
    final isExpanded = _expandedChannel == index;
    final freqLabel = ch.centerFreqHz >= 1000
        ? '${(ch.centerFreqHz / 1000).toStringAsFixed(ch.centerFreqHz % 1000 == 0 ? 0 : 1)}k'
        : '${ch.centerFreqHz.toInt()}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(
                () => _expandedChannel = isExpanded ? null : index),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 55,
                    child: Text('$freqLabel Hz',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ),
                  const Text('Gain', style: TextStyle(fontSize: 11)),
                  Expanded(
                    child: Slider(
                      value: ch.gainDb,
                      min: -20,
                      max: 60,
                      divisions: 80,
                      onChanged: (v) =>
                          dspService.updateChannelGain(index, v),
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                        '${ch.gainDb.toStringAsFixed(1)} dB',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11)),
                  ),
                  Icon(isExpanded
                      ? Icons.expand_less
                      : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  _paramSlider('Threshold', ch.thresholdDb, -60, 0, 'dB',
                      (v) => dspService.updateChannelThreshold(index, v)),
                  _paramSlider('Ratio', ch.ratio, 1.0, 10.0, ':1',
                      (v) => dspService.updateChannelRatio(index, v)),
                  _paramSlider('Attack', ch.attackMs, 1, 100, 'ms',
                      (v) => dspService.updateChannelAttack(index, v)),
                  _paramSlider('Release', ch.releaseMs, 10, 500, 'ms',
                      (v) => dspService.updateChannelRelease(index, v)),
                  _paramSlider('MPO', ch.mpoDbSpl, 80, 130, 'dB SPL',
                      (v) => dspService.updateChannelMpo(index, v)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _paramSlider(String label, double value, double min, double max,
      String unit, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
            width: 65,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 70,
          child: Text('${value.toStringAsFixed(1)} $unit',
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.right),
        ),
      ],
    );
  }

  Widget _buildActionBar(
      DspConfigService dspService, DeviceConnectionService connService) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: connService.isConnected
                  ? () async {
                      final ok = await dspService.uploadFullConfig();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(ok
                                ? 'Config uploaded'
                                : 'Upload failed')));
                      }
                    }
                  : null,
              icon: const Icon(Icons.upload),
              label: const Text('Upload'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: connService.isConnected
                  ? () async {
                      final ok = await dspService.readFromDevice();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                ok ? 'Config read' : 'Read failed')));
                      }
                    }
                  : null,
              icon: const Icon(Icons.download),
              label: const Text('Read'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => dspService.resetToDefaults(),
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
