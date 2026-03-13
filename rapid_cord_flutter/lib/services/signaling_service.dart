import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connection state of the signaling service.
enum SignalingState { disconnected, connecting, connected, error }

/// Types of signaling messages exchanged with the Go backend.
enum SignalType {
  join,
  leave,
  offer,
  answer,
  iceCandidate,
  chat,
  userList,
  roomState,
  error,

  /// Sent by a client that is vacating its WebSocket so a new isolate can
  /// take over the session without a visible leave/rejoin.
  handoffStart,

  /// Received from the server when a user completes a handoff reconnect.
  /// Existing peers should re-negotiate their peer connection with that user.
  handoffResume,

  /// Client → server: publishes Curve25519 public key, virtual IP, and
  /// public endpoint so the server can distribute them to room peers.
  wgAnnounce,

  /// Server → client: full updated WireGuard peer list for the room.
  /// Payload: `{ "peers": [ WGPeerInfo... ] }`
  wgPeerUpdate,
}

/// Maps server wire-format type strings to [SignalType].
const _serverTypeToSignal = <String, SignalType>{
  'user_join': SignalType.join,
  'user_leave': SignalType.leave,
  'join': SignalType.join,
  'leave': SignalType.leave,
  'offer': SignalType.offer,
  'answer': SignalType.answer,
  'ice_candidate': SignalType.iceCandidate,
  'iceCandidate': SignalType.iceCandidate,
  'chat': SignalType.chat,
  'chat_message': SignalType.chat, // server echoes back with this key
  'user_list': SignalType.userList,
  'userList': SignalType.userList,
  'room_state': SignalType.roomState,
  'error': SignalType.error,
  'handoff_resume': SignalType.handoffResume,
  'wg_announce': SignalType.wgAnnounce,
  'wg_peer_update': SignalType.wgPeerUpdate,
};

/// Maps [SignalType] to the wire-format type string the server expects.
const _signalToServerType = <SignalType, String>{
  SignalType.join: 'join',
  SignalType.leave: 'leave',
  SignalType.offer: 'offer',
  SignalType.answer: 'answer',
  SignalType.iceCandidate: 'ice_candidate',
  SignalType.chat: 'chat_message', // matches Go EventChatMessage constant
  SignalType.userList: 'user_list',
  SignalType.error: 'error',
  SignalType.handoffStart: 'handoff_start',
  SignalType.wgAnnounce: 'wg_announce',
};

/// A structured signaling message.
class SignalingMessage {
  final SignalType type;
  final String? from;
  final String? to;
  final Map<String, dynamic> payload;

  const SignalingMessage({
    required this.type,
    this.from,
    this.to,
    this.payload = const {},
  });

  factory SignalingMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? '';
    final signalType = _serverTypeToSignal[typeStr] ?? SignalType.error;

    // Server uses sender_id; fall back to from.
    final sender = (json['sender_id'] ?? json['from']) as String?;
    final target = (json['target_id'] ?? json['to']) as String?;

    // Server relays payloads under the "payload" key (Go struct tag).
    // Keep the "data" fallback for any legacy or third-party messages.
    final data =
        (json['payload'] as Map<String, dynamic>?) ??
        (json['data'] as Map<String, dynamic>?) ??
        {};

    return SignalingMessage(
      type: signalType,
      from: sender,
      to: target,
      payload: data,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': _signalToServerType[type] ?? type.name,
    if (to != null) 'target_id': to,
    // Must match the Go server's Message struct tag `json:"payload"`.
    if (payload.isNotEmpty) 'payload': payload,
  };
}

/// Manages the WebSocket connection to the Go signaling server.
///
/// Usage:
/// ```dart
/// final signaling = SignalingService();
/// signaling.connect('ws://10.147.17.199:8080/ws', userId: 'abc');
/// signaling.onMessage.listen((msg) { ... });
/// signaling.send(SignalingMessage(type: SignalType.offer, ...));
/// ```
class SignalingService {
  WebSocketChannel? _channel;
  SignalingState _state = SignalingState.disconnected;
  String? _serverUrl;
  String? _jwtToken;
  String? _roomId;
  bool _isHandoff = false;

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  bool _intentionalDisconnect = false;

  // ── Streams ──
  final _messageController = StreamController<SignalingMessage>.broadcast();
  final _stateController = StreamController<SignalingState>.broadcast();

  Stream<SignalingMessage> get onMessage => _messageController.stream;
  Stream<SignalingState> get onState => _stateController.stream;
  SignalingState get state => _state;

  /// Connect to the signaling server using a JWT for authentication.
  ///
  /// The server validates [jwtToken] on every WebSocket upgrade and derives
  /// the user identity from it — no separate `user_id` parameter is needed.
  ///
  /// Set [isHandoff] to `true` when reconnecting as part of a connection
  /// handoff (pop-out or pop-in). The server will skip the normal join
  /// announcement and broadcast `handoff_resume` to existing peers instead.
  void connect(
    String url, {
    required String jwtToken,
    required String roomId,
    bool isHandoff = false,
  }) {
    _intentionalDisconnect = false;
    _serverUrl = url;
    _jwtToken = jwtToken;
    _roomId = roomId;
    _isHandoff = isHandoff;
    _doConnect();
  }

  void _doConnect() {
    if (_state == SignalingState.connecting) return;
    _setState(SignalingState.connecting);

    try {
      final handoffParam = _isHandoff ? '&handoff=true' : '';
      final uri = Uri.parse(
        '$_serverUrl?token=$_jwtToken&room_id=$_roomId$handoffParam',
      );
      // Handoff flag is consumed by a single connection; reset so automatic
      // reconnects (after e.g. a transient network error) behave normally.
      _isHandoff = false;
      _channel = WebSocketChannel.connect(uri);

      _channel!.ready
          .then((_) {
            _setState(SignalingState.connected);
            _reconnectAttempts = 0;
            debugPrint('[SignalingService] Connected to $_serverUrl');
          })
          .catchError((Object error) {
            debugPrint('[SignalingService] Connection failed (ready): $error');
            _setState(SignalingState.error);
            _scheduleReconnect();
          });

      _channel!.stream.listen(
        (data) {
          try {
            final raw = (data as String).trim();
            if (raw.isEmpty) return;

            // Some servers send NDJSON (newline-delimited).
            final lines = raw.split('\n');
            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) continue;
              final json = jsonDecode(trimmed) as Map<String, dynamic>;
              final message = SignalingMessage.fromJson(json);
              debugPrint(
                '[SignalingService] ← ${json['type']} from ${message.from}',
              );
              _messageController.add(message);
            }
          } catch (e) {
            debugPrint('[SignalingService] Failed to parse message: $e');
            debugPrint('[SignalingService] Raw data: $data');
          }
        },
        onError: (error) {
          debugPrint('[SignalingService] WebSocket error: $error');
          _setState(SignalingState.error);
          _scheduleReconnect();
        },
        onDone: () {
          debugPrint('[SignalingService] WebSocket closed');
          _setState(SignalingState.disconnected);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[SignalingService] Connection failed: $e');
      _setState(SignalingState.error);
      _scheduleReconnect();
    }
  }

  /// Send a signaling message.
  void send(SignalingMessage message) {
    if (_state != SignalingState.connected || _channel == null) {
      debugPrint('[SignalingService] Cannot send — not connected');
      return;
    }
    final json = jsonEncode(message.toJson());
    debugPrint(
      '[SignalingService] → ${message.type.name} to=${message.to} len=${json.length}',
    );
    _channel!.sink.add(json);
  }

  /// Disconnect from the server.
  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(SignalingState.disconnected);
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[SignalingService] Max reconnect attempts reached');
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectAttempts++;
      debugPrint(
        '[SignalingService] Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts',
      );
      _doConnect();
    });
  }

  void _setState(SignalingState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// Dispose all resources.
  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
