import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_connection_service.dart';
import 'device_connection_screen.dart';
import 'audiogram_screen.dart';
import 'dsp_config_screen.dart';
import 'frequency_response_screen.dart';
import 'presets_screen.dart';

/// Main home screen with 5-tab navigation.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    DeviceConnectionScreen(),
    AudiogramScreen(),
    DspConfigScreen(),
    FrequencyResponseScreen(),
    ProfileManagementScreen(),
  ];

  final _titles = const [
    'Device Connection',
    'Audiogram',
    'DSP Configuration',
    'Visualization',
    'Profiles',
  ];

  @override
  Widget build(BuildContext context) {
    final connService = context.watch<DeviceConnectionService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        actions: [
          if (connService.isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                avatar: Icon(
                  connService.connectionType == ConnectionType.ble
                      ? Icons.bluetooth_connected
                      : Icons.usb,
                  size: 16,
                  color: Colors.green,
                ),
                label: Text(connService.connectedDeviceName,
                    style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bluetooth),
            selectedIcon: Icon(Icons.bluetooth_connected),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.hearing),
            selectedIcon: Icon(Icons.hearing),
            label: 'Audiogram',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            selectedIcon: Icon(Icons.tune),
            label: 'DSP Config',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Visualize',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder),
            selectedIcon: Icon(Icons.folder_open),
            label: 'Profiles',
          ),
        ],
      ),
    );
  }
}
