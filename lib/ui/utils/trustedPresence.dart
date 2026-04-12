/*! 
 * @file trusted_presence.dart
 * @brief Global trusted session presence broadcaster for LAN discovery.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class HostTransferRequestNotice {
  final String requestId;
  final String requesterId;
  final String requesterName;

  const HostTransferRequestNotice({
    required this.requestId,
    required this.requesterId,
    required this.requesterName,
  });
}

class TrustedPresenceService {
  TrustedPresenceService._();
  static final TrustedPresenceService instance = TrustedPresenceService._();

  static const String _kTrustedHostId = 'account.security.trusted.host_id';
  static const String _kTrustedInstanceId = 'account.security.trusted.instance_id';
  static const String _kAuthName = 'account.auth.name';
  static const String _kAuthPhoto = 'account.auth.photo';

  static const int _udpPort = 48321;
  static const String _packetProto = 'easync_trusted_v1';
  static const Duration _helloInterval = Duration(seconds: 3);

  RawDatagramSocket? _socket;
  Timer? _helloTimer;
  Timer? _retryTimer;
  bool _started = false;
  final Set<String> _seenRequestIds = <String>{};
  final Map<String, HostTransferRequestNotice> _pendingRequests =
      <String, HostTransferRequestNotice>{};
  final StreamController<HostTransferRequestNotice> _requestController =
      StreamController<HostTransferRequestNotice>.broadcast();

  Stream<HostTransferRequestNotice> get onHostTransferRequest =>
      _requestController.stream;

  List<HostTransferRequestNotice> pendingHostTransferRequests() {
    return _pendingRequests.values.toList(growable: false);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _ensureSocketBound();
  }

  Future<void> _ensureSocketBound() async {
    if (!_started) return;
    if (_socket != null) return;

    try {
      try {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _udpPort,
          reuseAddress: true,
          reusePort: true,
        );
      } catch (_) {
        _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _udpPort,
          reuseAddress: true,
        );
      }
      _socket?.broadcastEnabled = true;
      _socket?.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = _socket?.receive()) != null) {
          _handleDatagram(d!);
        }
      });

      _retryTimer?.cancel();
      _retryTimer = null;
      _sendHello();
      _helloTimer = Timer.periodic(_helloInterval, (_) => _sendHello());
    } catch (_) {
      _socket?.close();
      _socket = null;
      _helloTimer?.cancel();
      _helloTimer = null;
      _retryTimer ??= Timer.periodic(const Duration(seconds: 4), (_) async {
        await _ensureSocketBound();
      });
    }
  }

  Future<void> _sendHello() async {
    final socket = _socket;
    if (socket == null) return;

    final prefs = await SharedPreferences.getInstance();

    var instanceId = (prefs.getString(_kTrustedInstanceId) ?? '').trim();
    if (instanceId.isEmpty) {
      final n = Random.secure().nextInt(0x7fffffff).toRadixString(16);
      instanceId =
          '${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}-$n';
      await prefs.setString(_kTrustedInstanceId, instanceId);
    }

    var hostId = (prefs.getString(_kTrustedHostId) ?? '').trim();
    if (hostId.isEmpty) {
      hostId = instanceId;
      await prefs.setString(_kTrustedHostId, hostId);
    }

    final nameFromAuth = (prefs.getString(_kAuthName) ?? '').trim();
    final displayName = nameFromAuth.isNotEmpty
        ? nameFromAuth
        : '${Platform.operatingSystem.toUpperCase()} • EaSync';

    final rawPhoto = (prefs.getString(_kAuthPhoto) ?? '').trim();
    final photo = rawPhoto.startsWith('http') ? rawPhoto : '';

    final packet = {
      'proto': _packetProto,
      'type': 'hello',
      'instanceId': instanceId,
      'displayName': displayName,
      'platform': Platform.operatingSystem,
      'photo': photo,
      'hostId': hostId,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };

    final data = utf8.encode(jsonEncode(packet));
    try {
      socket.send(data, InternetAddress('255.255.255.255'), _udpPort);
    } catch (_) {}
  }

  Future<void> _handleDatagram(Datagram datagram) async {
    Map<String, dynamic>? packet;
    try {
      final text = utf8.decode(datagram.data, allowMalformed: true);
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        packet = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return;
    }
    if (packet == null || packet['proto'] != _packetProto) return;

    final type = (packet['type'] ?? '').toString().trim();

    if (type == 'host_transfer_result') {
      final requestId = (packet['requestId'] ?? '').toString().trim();
      if (requestId.isNotEmpty) {
        _pendingRequests.remove(requestId);
      }
      return;
    }

    if (type != 'host_transfer_request') return;

    final requestId = (packet['requestId'] ?? '').toString().trim();
    final requesterId = (packet['requesterId'] ?? '').toString().trim();
    if (requestId.isEmpty || requesterId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final localInstanceId = (prefs.getString(_kTrustedInstanceId) ?? '').trim();
    if (localInstanceId.isNotEmpty && requesterId == localInstanceId) return;

    if (_seenRequestIds.contains(requestId)) return;
    _seenRequestIds.add(requestId);
    if (_seenRequestIds.length > 128) {
      _seenRequestIds.remove(_seenRequestIds.first);
    }

    final requesterName = (packet['requesterName'] ?? '').toString().trim();
    final notice = HostTransferRequestNotice(
      requestId: requestId,
      requesterId: requesterId,
      requesterName: requesterName,
    );
    _pendingRequests[requestId] = notice;
    _requestController.add(
      notice,
    );
  }
}
