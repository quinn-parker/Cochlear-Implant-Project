import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Abstract transport layer for device communication.
/// Implemented by both BLE and Serial transports.
abstract class TransportLayer {
  Future<void> send(Uint8List data);
  Stream<Uint8List> get receiveStream;
  Future<void> disconnect();
  bool get isConnected;
}

/// BLE transport using flutter_blue_plus.
///
/// Connects to the hearing aid's custom GATT service and communicates
/// via the Config Write and Config Notify characteristics.
class BleTransport implements TransportLayer {
  static const String serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const String configWriteUuid = '12345678-1234-5678-1234-56789abcdef1';
  static const String configNotifyUuid = '12345678-1234-5678-1234-56789abcdef2';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  final _receiveController = StreamController<Uint8List>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get receiveStream => _receiveController.stream;

  /// Scan for hearing aid devices.
  static Stream<ScanResult> scan({Duration timeout = const Duration(seconds: 5)}) {
    FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: [Guid(serviceUuid)],
    );
    return FlutterBluePlus.scanResults.expand((results) => results);
  }

  static void stopScan() {
    FlutterBluePlus.stopScan();
  }

  /// Connect to a discovered BLE device.
  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect(autoConnect: false, mtu: 512);

    // Request higher MTU for config transfers
    await device.requestMtu(512);

    // Discover services
    final services = await device.discoverServices();
    final haService = services.firstWhere(
      (s) => s.uuid == Guid(serviceUuid),
      orElse: () => throw Exception('Hearing aid service not found'),
    );

    _writeChar = haService.characteristics.firstWhere(
      (c) => c.uuid == Guid(configWriteUuid),
      orElse: () => throw Exception('Config write characteristic not found'),
    );

    _notifyChar = haService.characteristics.firstWhere(
      (c) => c.uuid == Guid(configNotifyUuid),
      orElse: () => throw Exception('Config notify characteristic not found'),
    );

    // Subscribe to notifications
    await _notifyChar!.setNotifyValue(true);
    _notifyChar!.onValueReceived.listen((value) {
      _receiveController.add(Uint8List.fromList(value));
    });

    _connected = true;
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_writeChar == null || !_connected) {
      throw Exception('BLE not connected');
    }

    // Split into MTU-sized chunks if needed (MTU - 3 for ATT header)
    final mtu = _device?.mtuNow ?? 244;
    final chunkSize = mtu - 3;

    if (data.length <= chunkSize) {
      await _writeChar!.write(data.toList(), withoutResponse: false);
    } else {
      // Multi-packet write
      for (int offset = 0; offset < data.length; offset += chunkSize) {
        final end = (offset + chunkSize < data.length)
            ? offset + chunkSize
            : data.length;
        await _writeChar!.write(
          data.sublist(offset, end).toList(),
          withoutResponse: false,
        );
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
    _notifyChar = null;
  }
}

/// Serial (UART) transport placeholder.
///
/// Uses flutter_libserialport for USB serial communication.
/// Requires the flutter_libserialport package to be added to pubspec.yaml.
class SerialTransport implements TransportLayer {
  final _receiveController = StreamController<Uint8List>.broadcast();
  bool _connected = false;
  dynamic _port; // SerialPort instance (from flutter_libserialport)

  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get receiveStream => _receiveController.stream;

  /// List available serial ports.
  static List<String> availablePorts() {
    // TODO: return SerialPort.availablePorts when flutter_libserialport is added
    return [];
  }

  /// Open a serial port connection.
  Future<void> connect(String portName, {int baudRate = 115200}) async {
    // TODO: Implement when flutter_libserialport is added
    // _port = SerialPort(portName);
    // _port.openReadWrite();
    // _port.config.baudRate = baudRate;
    // _port.config.bits = 8;
    // _port.config.parity = SerialPortParity.none;
    // _port.config.stopBits = 1;
    // SerialPortReader(_port).stream.listen((data) {
    //   _receiveController.add(Uint8List.fromList(data));
    // });
    _connected = true;
  }

  @override
  Future<void> send(Uint8List data) async {
    if (!_connected || _port == null) {
      throw Exception('Serial port not connected');
    }
    // TODO: _port.write(data);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    // TODO: _port?.close();
    _port = null;
  }
}
