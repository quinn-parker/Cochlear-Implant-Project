import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_connection_service.dart';

/// Screen for scanning and connecting to hearing aid devices via BLE
class DeviceConnectionScreen extends StatelessWidget {
  const DeviceConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceService = context.watch<DeviceConnectionService>();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Scan button
          ElevatedButton.icon(
            onPressed: deviceService.isScanning 
              ? null 
              : () => deviceService.startScan(),
            icon: deviceService.isScanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bluetooth_searching),
            label: Text(deviceService.isScanning ? 'Scanning...' : 'Scan for Devices'),
          ),
          
          const SizedBox(height: 24),
          
          // Section header
          Text(
            'Available Devices',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(),
          
          // Device list
          Expanded(
            child: deviceService.discoveredDevices.isEmpty
              ? const Center(
                  child: Text(
                    'No devices found.\nMake sure your hearing aids are powered on.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: deviceService.discoveredDevices.length,
                  itemBuilder: (context, index) {
                    final device = deviceService.discoveredDevices[index];
                    return _DeviceListTile(device: device);
                  },
                ),
          ),
          
          // Connected device info
          if (deviceService.isConnected) ...[
            const Divider(),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bluetooth_connected, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Connected Device',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Name: ${deviceService.connectedDeviceName}'),
                    Text('Firmware: ${deviceService.firmwareVersion}'),
                    Text('Battery: ${deviceService.batteryLevel}%'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => deviceService.disconnect(),
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final DiscoveredDevice device;

  const _DeviceListTile({required this.device});

  @override
  Widget build(BuildContext context) {
    final deviceService = context.read<DeviceConnectionService>();

    return ListTile(
      leading: const Icon(Icons.hearing),
      title: Text(device.name),
      subtitle: Text('Signal: ${device.rssi} dBm'),
      trailing: ElevatedButton(
        onPressed: () => deviceService.connect(device),
        child: const Text('Connect'),
      ),
    );
  }
}
