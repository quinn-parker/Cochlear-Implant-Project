import 'dart:async';
import 'dart:typed_data';
import '../models/channel_config.dart';
import '../models/hearing_aid_profile.dart';
import 'transport.dart';

/// Device status read from firmware.
class DeviceStatus {
  final int firmwareMajor;
  final int firmwareMinor;
  final int firmwarePatch;
  final int numChannels;
  final int sampleRate;
  final int fftSize;
  final double agcGainDb;
  final bool noiseEstimated;
  final bool processingEnabled;

  DeviceStatus({
    required this.firmwareMajor,
    required this.firmwareMinor,
    required this.firmwarePatch,
    required this.numChannels,
    required this.sampleRate,
    required this.fftSize,
    required this.agcGainDb,
    required this.noiseEstimated,
    required this.processingEnabled,
  });

  String get firmwareVersionString =>
      'v$firmwareMajor.$firmwareMinor.$firmwarePatch';
}

/// Handles the binary protocol for communicating with the hearing aid firmware.
///
/// Protocol frame: [cmd:1][length:2 LE][payload:N][checksum:1 XOR]
/// Works identically over UART and BLE transports.
class ProtocolService {
  final TransportLayer transport;
  final Duration timeout;

  /// Stream of incoming response bytes, buffered.
  StreamSubscription<Uint8List>? _subscription;
  final _responseBuffer = <int>[];
  Completer<Uint8List>? _responseCompleter;

  ProtocolService({
    required this.transport,
    this.timeout = const Duration(seconds: 3),
  }) {
    _subscription = transport.receiveStream.listen(_onDataReceived);
  }

  void dispose() {
    _subscription?.cancel();
  }

  void _onDataReceived(Uint8List data) {
    _responseBuffer.addAll(data);
    _tryParseResponse();
  }

  void _tryParseResponse() {
    // Need at least cmd + 2 length bytes
    if (_responseBuffer.length < 3) return;

    final cmd = _responseBuffer[0];
    final payloadLen =
        _responseBuffer[1] | (_responseBuffer[2] << 8);
    final totalLen = 3 + payloadLen;

    if (_responseBuffer.length >= totalLen) {
      final frame = Uint8List.fromList(_responseBuffer.sublist(0, totalLen));
      _responseBuffer.removeRange(0, totalLen);

      if (_responseCompleter != null && !_responseCompleter!.isCompleted) {
        _responseCompleter!.complete(frame);
      }
    }
  }

  /// Wait for a response frame from the device.
  Future<Uint8List> _waitForResponse() async {
    _responseCompleter = Completer<Uint8List>();
    // Check if data already buffered
    _tryParseResponse();
    return _responseCompleter!.future.timeout(timeout,
        onTimeout: () => throw TimeoutException('No response from device'));
  }

  /// Compute XOR checksum of payload bytes.
  static int _checksum(Uint8List data) {
    int cs = 0;
    for (final b in data) {
      cs ^= b;
    }
    return cs;
  }

  /// Build a protocol frame: [cmd][len_lo][len_hi][payload][checksum].
  static Uint8List _buildFrame(int cmd, Uint8List payload) {
    final len = payload.length + 1; // payload + checksum
    final frame = BytesBuilder();
    frame.addByte(cmd);
    frame.addByte(len & 0xFF);
    frame.addByte((len >> 8) & 0xFF);
    frame.add(payload);
    frame.addByte(_checksum(payload));
    return frame.toBytes();
  }

  /// Build a frame with empty payload (for read requests).
  static Uint8List _buildEmptyFrame(int cmd) {
    return Uint8List.fromList([cmd, 0, 0]);
  }

  /// Send full 12-channel config to device.
  Future<bool> writeFullConfig(List<ChannelConfig> channels) async {
    final payload = BytesBuilder();
    for (final ch in channels) {
      payload.add(ch.toBytes());
    }
    final frame = _buildFrame(0x57 /* 'W' */, payload.toBytes());
    await transport.send(frame);

    final resp = await _waitForResponse();
    return resp.isNotEmpty && resp[0] == 0x41; // 'A' = ACK
  }

  /// Send a single channel update (fast, for real-time slider adjustment).
  Future<bool> writeSingleChannel(ChannelConfig channel) async {
    final payload = BytesBuilder();
    payload.addByte(channel.index);
    payload.add(channel.toBytes());
    final frame = _buildFrame(0x77 /* 'w' */, payload.toBytes());
    await transport.send(frame);

    final resp = await _waitForResponse();
    return resp.isNotEmpty && resp[0] == 0x41;
  }

  /// Send global config (master volume, noise reduction, HF emphasis).
  Future<bool> writeGlobalConfig(HearingAidProfile profile) async {
    final payload = profile.globalToFirmwareBinary();
    final frame = _buildFrame(0x47 /* 'G' */, payload);
    await transport.send(frame);

    final resp = await _waitForResponse();
    return resp.isNotEmpty && resp[0] == 0x41;
  }

  /// Read current device configuration.
  Future<List<ChannelConfig>?> readDeviceConfig() async {
    final frame = _buildEmptyFrame(0x52 /* 'R' */);
    await transport.send(frame);

    final resp = await _waitForResponse();
    if (resp.isEmpty || resp[0] != 0x72 /* 'r' */) return null;

    final payloadLen = resp[1] | (resp[2] << 8);
    final payload = resp.sublist(3, 3 + payloadLen - 1); // exclude checksum

    final channels = <ChannelConfig>[];
    for (int i = 0; i < 12; i++) {
      final offset = i * ChannelConfig.wireSize;
      if (offset + ChannelConfig.wireSize > payload.length) break;
      channels.add(ChannelConfig.fromBytes(
        i,
        Uint8List.sublistView(payload, offset, offset + ChannelConfig.wireSize),
      ));
    }
    return channels;
  }

  /// Read device status.
  Future<DeviceStatus?> readStatus() async {
    final frame = _buildEmptyFrame(0x53 /* 'S' */);
    await transport.send(frame);

    final resp = await _waitForResponse();
    if (resp.isEmpty || resp[0] != 0x73 /* 's' */) return null;

    final payload = resp.sublist(3);
    if (payload.length < 12) return null;

    final data = ByteData.sublistView(Uint8List.fromList(payload));
    return DeviceStatus(
      firmwareMajor: data.getUint8(0),
      firmwareMinor: data.getUint8(1),
      firmwarePatch: data.getUint8(2),
      numChannels: data.getUint8(3),
      sampleRate: data.getUint16(4, Endian.little),
      fftSize: data.getUint16(6, Endian.little),
      agcGainDb: data.getFloat32(8, Endian.little),
      noiseEstimated: data.getUint8(12) != 0,
      processingEnabled: data.getUint8(13) != 0,
    );
  }
}
