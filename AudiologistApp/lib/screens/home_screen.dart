import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_connection_service.dart';
import 'device_connection_screen.dart';
import 'dsp_config_screen.dart';
import 'frequency_response_screen.dart';
import 'presets_screen.dart';

/// Main navigation hub for the audiologist app
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    DeviceConnectionScreen(),
    DspConfigScreen(),
    FrequencyResponseScreen(),
    PresetsScreen(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.bluetooth_searching),
      selectedIcon: Icon(Icons.bluetooth_connected),
      label: 'Devices',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune),
      selectedIcon: Icon(Icons.tune),
      label: 'DSP Config',
    ),
    NavigationDestination(
      icon: Icon(Icons.show_chart),
      selectedIcon: Icon(Icons.show_chart),
      label: 'Response',
    ),
    NavigationDestination(
      icon: Icon(Icons.save),
      selectedIcon: Icon(Icons.save),
      label: 'Presets',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final deviceService = context.watch<DeviceConnectionService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiologist DSP Config'),
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  deviceService.isConnected 
                    ? Icons.bluetooth_connected 
                    : Icons.bluetooth_disabled,
                  color: deviceService.isConnected 
                    ? Colors.green 
                    : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  deviceService.isConnected 
                    ? 'Connected' 
                    : 'Disconnected',
                  style: TextStyle(
                    color: deviceService.isConnected 
                      ? Colors.green 
                      : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _destinations,
      ),
    );
  }
}
