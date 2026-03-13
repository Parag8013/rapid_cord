import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:wireguard_flutter/wireguard_flutter.dart';

/// Singleton that owns the device's WireGuard identity and manages the VPN tunnel.
///
/// Lifecycle:
///  1. Call [init] once after authentication to generate Curve25519 keys,
///     discover the public IP, and assign a virtual IP.
///  2. Call [updatePeers] whenever the server broadcasts a `wg_peer_update`
///     to rebuild the tunnel configuration and activate it.
///  3. Call [stopTunnel] when leaving the call.
class WireGuardService {
  WireGuardService._();
  static final WireGuardService instance = WireGuardService._();

  String? _privateKeyB64;

  /// Base64-encoded Curve25519 public key for this device.
  String? publicKey;

  /// Virtual IP address (10.0.x.x) assigned to this device in the mesh.
  String? virtualIP;

  /// Public endpoint (IP:51820) discovered via ipify.org.
  String? publicEndpoint;

  bool _initialized = false;
  bool _tunnelRunning = false;

  bool get isInitialized => _initialized;

  // ── Initialisation ──────────────────────────────────────────────────────────

  /// Generate WireGuard keys, discover the public IP, and assign a virtual IP.
  ///
  /// Idempotent — subsequent calls are no-ops once initialised.
  Future<void> init(String userId) async {
    if (_initialized) return;

    // ── Key generation ────────────────────────────────────────────────────────
    // WireGuard uses Curve25519 (X25519 Diffie-Hellman). Generate a key pair
    // and base64-encode both halves.
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKeyObj = await keyPair.extractPublicKey();

    _privateKeyB64 = base64Encode(Uint8List.fromList(privateKeyBytes));
    publicKey = base64Encode(Uint8List.fromList(publicKeyObj.bytes));

    // ── Virtual IP assignment ─────────────────────────────────────────────────
    virtualIP = _assignVirtualIP(userId);

    // ── Public endpoint discovery ─────────────────────────────────────────────
    try {
      final response = await http
          .get(Uri.parse('https://api.ipify.org'))
          .timeout(const Duration(seconds: 2));
      final ip = response.body.trim();
      publicEndpoint = '$ip:51820';
    } catch (e) {
      debugPrint('[WireGuardService] Public IP discovery failed: $e');
      // Fall back gracefully — peers cannot initiate connections to us but
      // we can still reach peers whose endpoints are reachable.
      publicEndpoint = '0.0.0.0:51820';
    }

    _initialized = true;
    debugPrint(
      '[WireGuardService] Initialised — '
      'pubkey=${publicKey?.substring(0, 8)}... '
      'vip=$virtualIP endpoint=$publicEndpoint',
    );
  }

  // ── Virtual IP assignment ───────────────────────────────────────────────────

  /// Deterministically maps [userId] to a 10.0.x.x address.
  ///
  /// Uses the low 16 bits of the userId hash, keeping both octets in 1–254 to
  /// avoid the network (.0) and broadcast (.255) addresses.
  String _assignVirtualIP(String userId) {
    final hash = userId.hashCode.abs();
    final o3 = ((hash >> 8) & 0xFF) % 254 + 1;
    final o4 = (hash & 0xFF) % 254 + 1;
    return '10.0.$o3.$o4';
  }

  // ── Tunnel management ───────────────────────────────────────────────────────

  /// Rebuild and apply the WireGuard tunnel from the server-broadcast peer list.
  ///
  /// [serverPeers] is the `peers` array from a `wg_peer_update` message; each
  /// element is a Map with keys: `user_id`, `username`, `wg_pub_key`,
  /// `virtual_ip`, `public_endpoint`.
  Future<void> updatePeers(List<dynamic> serverPeers) async {
    if (!_initialized || _privateKeyB64 == null) {
      debugPrint(
        '[WireGuardService] updatePeers called before init — skipping',
      );
      return;
    }

    final peers = serverPeers
        .whereType<Map<String, dynamic>>()
        .where((p) => (p['wg_pub_key'] as String? ?? '').isNotEmpty)
        .toList();

    // ── Build wg-quick configuration string ───────────────────────────────────
    final buf = StringBuffer()
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $_privateKeyB64')
      ..writeln('Address = $virtualIP/24')
      ..writeln('DNS = 1.1.1.1')
      ..writeln('ListenPort = 51820')
      ..writeln();

    for (final p in peers) {
      final peerPubKey = p['wg_pub_key'] as String;
      final peerVIP = p['virtual_ip'] as String? ?? '';
      final peerEndpoint = p['public_endpoint'] as String? ?? '';

      buf.writeln('[Peer]');
      buf.writeln('PublicKey = $peerPubKey');
      if (peerVIP.isNotEmpty) {
        buf.writeln('AllowedIPs = $peerVIP/32');
      }
      if (peerEndpoint.isNotEmpty) {
        buf.writeln('Endpoint = $peerEndpoint');
      }
      buf
        ..writeln('PersistentKeepalive = 25')
        ..writeln();
    }

    final config = buf.toString();
    final firstEndpoint = peers.isNotEmpty
        ? (peers.first['public_endpoint'] as String? ?? '')
        : '';

    try {
      final wg = WireGuardFlutter.instance;
      if (!_tunnelRunning) {
        await wg.initialize(interfaceName: 'wg0');
      }
      await wg.startVpn(
        serverAddress: firstEndpoint,
        wgQuickConfig: config,
        // providerBundleIdentifier is required on iOS for the Network Extension.
        providerBundleIdentifier: 'com.example.rapidcord',
      );
      _tunnelRunning = true;
      debugPrint(
        '[WireGuardService] Tunnel updated with ${peers.length} peer(s)',
      );
    } catch (e) {
      debugPrint('[WireGuardService] Failed to apply tunnel config: $e');
    }
  }

  /// Stop the WireGuard tunnel (call when leaving a voice channel).
  Future<void> stopTunnel() async {
    if (!_tunnelRunning) return;
    try {
      await WireGuardFlutter.instance.stopVpn();
      _tunnelRunning = false;
      debugPrint('[WireGuardService] Tunnel stopped');
    } catch (e) {
      debugPrint('[WireGuardService] Failed to stop tunnel: $e');
    }
  }
}
