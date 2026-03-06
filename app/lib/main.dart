/// Audiologist DSP Configuration App
/// Cochlear Implant Project - Bone Conduction Hearing Aid
///
/// Clinical-grade fitting tool for audiologists:
/// - Enter patient audiogram and auto-fit gain prescription (NAL-NL2 style)
/// - Configure 12-channel WDRC with per-band gain, compression, MPO
/// - Visualize frequency response and I/O functions
/// - Connect via Bluetooth LE or USB serial
/// - Save/load .haprofile patient files

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/device_connection_service.dart';
import 'services/dsp_config_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AudiologistApp());
}

class AudiologistApp extends StatelessWidget {
  const AudiologistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceConnectionService()),
        ChangeNotifierProxyProvider<DeviceConnectionService, DspConfigService>(
          create: (ctx) => DspConfigService(ctx.read<DeviceConnectionService>()),
          update: (ctx, conn, prev) => prev ?? DspConfigService(conn),
        ),
      ],
      child: MaterialApp(
        title: 'Hearing Aid Fitting Tool',
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
