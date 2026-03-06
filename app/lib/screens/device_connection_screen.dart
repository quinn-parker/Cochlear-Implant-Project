import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_connection_service.dart';

/// Device connection screen supporting BLE and Serial connections.
class DeviceConnectionScreen extends StatelessWidget {
  const DeviceConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceConnectionService>(
      builder: (context, connService, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connected device info
              if (connService.isConnected) _buildConnectedCard(connService, context),

              if (!connService.isConnected) ...[
                // BLE Scan
                const Text('Bluetooth',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: connService.isScanning
                      ? () => connService.stopScan()
                      : () => connService.startBleScan(),
                  icon: Icon(connService.isScanning
                      ? Icons.stop
                      : Icons.bluetooth_searching),
                  label: Text(
                      connService.isScanning ? 'Stop Scan' : 'Scan for Devices'),
                ),
                const SizedBox(height: 8),

                if (connService.isScanning)
                  const Center(child: CircularProgressIndicator()),

                // Discovered devices
                ...connService.discoveredDevices.map((device) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.name),
                        subtitle: Text('RSSI: ${device.rssi} dBm'),
                        trailing: FilledButton(
                          onPressed: () => connService.connectBle(device),
                          child: const Text('Connect'),
                        ),
                      ),
                    )),

                const SizedBox(height: 20),

                // Serial connection
                const Text('Serial (USB)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildSerialSection(connService, context),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildConnectedCard(
      DeviceConnectionService connService, BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  connService.connectionType == ConnectionType.ble
                      ? Icons.bluetooth_connected
                      : Icons.usb,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                const Text('Connected',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green)),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow('Device', connService.connectedDeviceName),
            _infoRow('Connection',
                connService.connectionType == ConnectionType.ble
                    ? 'Bluetooth LE'
                    : 'Serial/USB'),
            _infoRow('Firmware', connService.firmwareVersion),
            if (connService.numChannels > 0)
              _infoRow('Channels', '${connService.numChannels}'),
            if (connService.sampleRate > 0)
              _infoRow('Sample Rate', '${connService.sampleRate} Hz'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => connService.disconnect(),
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSerialSection(
      DeviceConnectionService connService, BuildContext context) {
    final ports = connService.getSerialPorts();
    if (ports.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No serial ports detected.\n'
            'Connect the nRF54L15-DK via USB and ensure drivers are installed.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: ports
          .map((port) => Card(
                child: ListTile(
                  leading: const Icon(Icons.usb),
                  title: Text(port),
                  trailing: FilledButton(
                    onPressed: () => connService.connectSerial(port),
                    child: const Text('Connect'),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:',
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(value),
        ],
      ),
    );
  }
}
