import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'transport.dart';
import 'protocol_service.dart';

/// Connection type enum.
enum ConnectionType { none, ble, serial }

/// Model for discovered BLE devices.
class DiscoveredDevice {
  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice? bleDevice;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.rssi,
    this.bleDevice,
  });
}

/// Manages device connections (BLE and Serial) and exposes a ProtocolService.
class DeviceConnectionService extends ChangeNotifier {
  // Connection state
  bool _isConnected = false;
  bool _isScanning = false;
  ConnectionType _connectionType = ConnectionType.none;

  // Device info
  String _connectedDeviceName = '';
  String _firmwareVersion = '';
  int _numChannels = 0;
  int _sampleRate = 0;

  // Transport and protocol
  TransportLayer? _transport;
  ProtocolService? _protocol;

  // Discovered devices
  final List<DiscoveredDevice> _discoveredDevices = [];

  // Getters
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  ConnectionType get connectionType => _connectionType;
  String get connectedDeviceName => _connectedDeviceName;
  String get firmwareVersion => _firmwareVersion;
  int get numChannels => _numChannels;
  int get sampleRate => _sampleRate;
  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  ProtocolService? get protocol => _protocol;
  TransportLayer? get transport => _transport;

  /// Start scanning for BLE hearing aid devices.
  Future<void> startBleScan() async {
    _isScanning = true;
    _discoveredDevices.clear();
    notifyListeners();

    try {
      FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        withServices: [Guid(BleTransport.serviceUuid)],
      );

      FlutterBluePlus.scanResults.listen((results) {
        _discoveredDevices.clear();
        for (final r in results) {
          _discoveredDevices.add(DiscoveredDevice(
            id: r.device.remoteId.str,
            name: r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : r.device.remoteId.str,
            rssi: r.rssi,
            bleDevice: r.device,
          ));
        }
        notifyListeners();
      });

      // Also add simulated devices in debug mode
      if (kDebugMode && _discoveredDevices.isEmpty) {
        await Future.delayed(const Duration(seconds: 3));
        if (_discoveredDevices.isEmpty) {
          _discoveredDevices.addAll([
            DiscoveredDevice(
                id: 'sim_left', name: 'BoneCond HA - Left (sim)', rssi: -45),
            DiscoveredDevice(
                id: 'sim_right', name: 'BoneCond HA - Right (sim)', rssi: -52),
          ]);
        }
      }
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Stop BLE scanning.
  void stopScan() {
    FlutterBluePlus.stopScan();
    _isScanning = false;
    notifyListeners();
  }

  /// Get available serial ports.
  List<String> getSerialPorts() {
    return SerialTransport.availablePorts();
  }

  /// Connect to a BLE device.
  Future<void> connectBle(DiscoveredDevice device) async {
    if (device.bleDevice == null) {
      // Simulated device in debug mode
      _isConnected = true;
      _connectionType = ConnectionType.ble;
      _connectedDeviceName = device.name;
      _firmwareVersion = 'Simulated';
      _numChannels = 12;
      _sampleRate = 16000;
      notifyListeners();
      return;
    }

    final bleTransport = BleTransport();
    await bleTransport.connect(device.bleDevice!);

    _transport = bleTransport;
    _protocol = ProtocolService(transport: bleTransport);

    _isConnected = true;
    _connectionType = ConnectionType.ble;
    _connectedDeviceName = device.name;
    notifyListeners();

    // Read device status
    await _readDeviceInfo();
  }

  /// Connect to a serial port.
  Future<void> connectSerial(String portName) async {
    final serialTransport = SerialTransport();
    await serialTransport.connect(portName);

    _transport = serialTransport;
    _protocol = ProtocolService(transport: serialTransport);

    _isConnected = true;
    _connectionType = ConnectionType.serial;
    _connectedDeviceName = portName;
    notifyListeners();

    await _readDeviceInfo();
  }

  /// Read firmware version and capabilities from device.
  Future<void> _readDeviceInfo() async {
    try {
      final status = await _protocol?.readStatus();
      if (status != null) {
        _firmwareVersion = status.firmwareVersionString;
        _numChannels = status.numChannels;
        _sampleRate = status.sampleRate;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to read device info: $e');
    }
  }

  /// Disconnect from current device.
  Future<void> disconnect() async {
    _protocol?.dispose();
    _protocol = null;
    await _transport?.disconnect();
    _transport = null;

    _isConnected = false;
    _connectionType = ConnectionType.none;
    _connectedDeviceName = '';
    _firmwareVersion = '';
    _numChannels = 0;
    _sampleRate = 0;

    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
