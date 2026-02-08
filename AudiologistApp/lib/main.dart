/// Audiologist DSP Configuration App
/// Cochlear Implant Project - Bone Conduction Hearing Aid
///
/// This application allows audiologists to:
/// - Connect to hearing aid devices via BLE
/// - Configure DSP parameters (filters, gain, compression)
/// - Visualize frequency response curves
/// - Save and load patient presets
/// - Run real-time audio tests

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/device_connection_service.dart';
import 'services/dsp_config_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const AudiologistApp());
}

class AudiologistApp extends StatelessWidget {
  const AudiologistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceConnectionService()),
        ChangeNotifierProvider(create: (_) => DspConfigService()),
      ],
      child: MaterialApp(
        title: 'Audiologist DSP Config',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      ),
    );
  }
}
