import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/media_quality.dart';
import '../models/message.dart';
import '../services/signaling_service.dart';
import '../services/sound_service.dart';
import '../services/webrtc_service.dart';
import '../services/wireguard_service.dart';

/// Central orchestrator connecting SignalingService ↔ WebRTCService.
///
/// Handles:
/// - Wiring incoming signaling messages to WebRTC methods
/// - Managing call lifecycle (join/leave)
/// - Exposing video renderers for the UI
/// - Forwarding media toggles to WebRTC tracks
class CallProvider extends ChangeNotifier {
  final SignalingService _signaling = SignalingService();
  late final WebRTCService _webrtc;
  StreamSubscription<SignalingMessage>? _messageSub;
  StreamSubscription<SignalingState>? _stateSub;
  StreamSubscription<MediaStream>? _remoteStreamSub;

  bool _isInCall = false;
  bool _initialized = false;
  String? _currentChannelId;
  String? _serverUrl;
  String? _userId;
  String? _jwtToken;
  String? _remotePeerId;

  // ── WireGuard / ICE ordering ──
  // The peer connection must not be initialized until after the WireGuard
  // tunnel is up so that the 10.x.x.x virtual interface is included in ICE
  // candidate gathering.  Signals that arrive before the tunnel is ready are
  // buffered and replayed once initPeerConnection() completes.
  bool _peerConnectionReady = false;
  bool _pendingOffer = false; // a role decision was made but PC not ready
  bool _pendingShouldOffer = false; // true → we offer; false → we wait
  Map<String, dynamic>? _pendingIncomingOffer; // offer SDP arrived early
  final List<Map<String, dynamic>> _pendingIceCandidates = [];

  // ── Room membership ──
  final List<String> _roomMembers = [];

  // ── Peer display names (userId → username) ──
  final Map<String, String> _peerNames = {};
  // ── Speaking states ──
  final Map<String, bool> _speakingStates = {};
  StreamSubscription<Map<String, bool>>? _speakingSub;

  // ── Incoming chat relay ──
  final _chatController =
      StreamController<({String channelId, ChatMessage message})>.broadcast();
  Stream<({String channelId, ChatMessage message})> get onIncomingChat =>
      _chatController.stream;

  CallProvider() {
    _webrtc = WebRTCService(_signaling);
  }

  // ── Getters ──
  bool get isInCall => _isInCall;
  bool get isInitialized => _initialized;
  String? get currentChannelId => _currentChannelId;
  SignalingState get signalingState => _signaling.state;
  RTCVideoRenderer get localRenderer => _webrtc.localRenderer;
  RTCVideoRenderer get remoteRenderer => _webrtc.remoteRenderer;
  RTCVideoRenderer get screenRenderer => _webrtc.screenRenderer;
  WebRTCService get webrtcService => _webrtc;
  bool get hasRemoteStream => _webrtc.remoteStream != null;
  bool get isScreenSharing => _webrtc.isScreenSharing;
  bool get isRemoteScreenSharing =>
      _webrtc.remoteScreenRenderer.srcObject != null;
  RTCVideoRenderer get remoteScreenRenderer => _webrtc.remoteScreenRenderer;
  Map<String, bool> get speakingStates => Map.unmodifiable(_speakingStates);
  Stream<double> get onLocalAudioLevelChanged =>
      _webrtc.onLocalAudioLevelChanged;
  bool isSpeaking(String userId) => _speakingStates[userId] ?? false;
  bool get isLocalSpeaking => _speakingStates[_userId ?? 'local'] ?? false;
  bool get isRemoteSpeaking => _remotePeerId != null
      ? (_speakingStates[_remotePeerId!] ?? false)
      : false;
  List<String> get roomMembers => List.unmodifiable(_roomMembers);
  String? get serverUrl => _serverUrl;
  String? get userId => _userId;

  /// Username of the remote peer, or null if not yet known.
  String? get remotePeerName =>
      _remotePeerId != null ? _peerNames[_remotePeerId!] : null;

  /// Returns the display name for [uid], or [uid] itself if unknown.
  String peerName(String uid) => _peerNames[uid] ?? uid;

  /// Configure the signaling server URL, user ID, and JWT token.
  ///
  /// Must be called before [joinCall] or [handoffJoin].
  void configure({
    required String serverUrl,
    required String userId,
    required String jwtToken,
  }) {
    _serverUrl = serverUrl;
    _userId = userId;
    _jwtToken = jwtToken;
  }

  /// Initialize renderers (call once at startup).
  Future<void> initialize() async {
    if (_initialized) return;
    await _webrtc.initialize();
    _initialized = true;
    notifyListeners();
  }

  /// Join a voice channel call.
  ///
  /// 1. Connects to the signaling server
  /// 2. Opens local camera + mic via getUserMedia
  /// 3. Creates an RTCPeerConnection with ICE handling
  /// 4. Sends a 'join' message so the server notifies other peers
  Future<void> joinCall(
    String channelId, {
    MediaQualitySettings? qualitySettings,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
  }) async {
    if (_isInCall) await leaveCall();
    if (!_initialized) await initialize();

    _currentChannelId = channelId;
    _isInCall = true;
    _roomMembers.clear();
    if (_userId != null) _roomMembers.add(_userId!);
    _peerConnectionReady = false;
    _pendingOffer = false;
    _pendingShouldOffer = false;
    _pendingIncomingOffer = null;
    _pendingIceCandidates.clear();
    notifyListeners();

    // Open local media FIRST so the camera is active and localRenderer is set.
    // Peer connection init is intentionally deferred until after the WireGuard
    // tunnel is established (see wgPeerUpdate handler) so the 10.x.x.x virtual
    // interface is visible during ICE candidate gathering.
    try {
      await _webrtc.openUserMedia(
        video: true,
        audio: true,
        settings: qualitySettings,
        audioInputDeviceId: audioInputDeviceId,
      );
      // Apply saved output device immediately so remote audio plays correctly.
      if (audioOutputDeviceId != null && audioOutputDeviceId.isNotEmpty) {
        await _webrtc.setAudioOutput(audioOutputDeviceId);
      }

      // Listen for incoming remote streams.
      _remoteStreamSub = _webrtc.onRemoteStream.listen((_) {
        debugPrint('[CallProvider] Remote stream received — notifying UI');
        notifyListeners();
      });

      // Track speaking status for all participants.
      _speakingSub = _webrtc.onSpeakingChanged.listen((states) {
        var changed = false;
        // Map internal 'local'/'remote' keys to real userIds.
        if (states.containsKey('local')) {
          final key = _userId ?? 'local';
          if (_speakingStates[key] != states['local']) {
            _speakingStates[key] = states['local']!;
            changed = true;
          }
        }
        if (states.containsKey('remote') && _remotePeerId != null) {
          if (_speakingStates[_remotePeerId!] != states['remote']) {
            _speakingStates[_remotePeerId!] = states['remote']!;
            changed = true;
          }
        }
        if (changed) notifyListeners();
      });

      debugPrint(
        '[CallProvider] Media opened — peer connection deferred until WireGuard is up',
      );
    } catch (e) {
      debugPrint('[CallProvider] Failed to open media: $e');
    }

    // Initialise WireGuard keys + endpoint BEFORE opening the signaling
    // connection so the announce can fire the moment the socket is established.
    if (_userId != null) {
      await WireGuardService.instance.init(_userId!);
    }

    // NOW connect to signaling — the server will notify existing peers about us.
    if (_serverUrl != null && _jwtToken != null) {
      _listenToSignaling();
      _listenToSignalingState();
      _signaling.connect(_serverUrl!, jwtToken: _jwtToken!, roomId: channelId);
    }

    debugPrint('[CallProvider] Joined call on channel: $channelId');
    notifyListeners();
  }

  /// Send `handoff_start` to the server and cleanly tear down the local
  /// connection WITHOUT broadcasting a `leave` message.
  ///
  /// Call this instead of [leaveCall] when popping out or popping back in.
  /// The server will keep the user's roster slot alive for 5 seconds so
  /// a seamless handoff can complete.
  Future<void> sendHandoffStart() async {
    if (_signaling.state == SignalingState.connected &&
        _currentChannelId != null) {
      _signaling.send(
        SignalingMessage(
          type: SignalType.handoffStart,
          payload: {'channel_id': _currentChannelId!},
        ),
      );
      // Give the frame time to flush before closing the socket.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    _messageSub?.cancel();
    _messageSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _remoteStreamSub?.cancel();
    _remoteStreamSub = null;
    _speakingSub?.cancel();
    _speakingSub = null;
    _speakingStates.clear();
    _roomMembers.clear();
    _peerNames.clear();
    await _webrtc.closePeerConnection();
    _signaling.disconnect();
    _isInCall = false;
    _currentChannelId = null;
    _remotePeerId = null;
    _peerConnectionReady = false;
    _pendingOffer = false;
    _pendingIncomingOffer = null;
    _pendingIceCandidates.clear();
    notifyListeners();
    debugPrint('[CallProvider] Handoff started — connection handed off');
  }

  /// Join a call as the completing side of a handoff.
  ///
  /// Identical to [joinCall] but passes [isHandoff] to the signaling service
  /// so the server treats this connection as `handoff_complete` instead of a
  /// fresh join.
  Future<void> handoffJoin(
    String channelId, {
    MediaQualitySettings? qualitySettings,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
  }) async {
    if (_isInCall) await leaveCall();
    if (!_initialized) await initialize();

    _currentChannelId = channelId;
    _isInCall = true;
    _roomMembers.clear();
    if (_userId != null) _roomMembers.add(_userId!);
    _peerConnectionReady = false;
    _pendingOffer = false;
    _pendingShouldOffer = false;
    _pendingIncomingOffer = null;
    _pendingIceCandidates.clear();
    notifyListeners();

    try {
      await _webrtc.openUserMedia(
        video: true,
        audio: true,
        settings: qualitySettings,
        audioInputDeviceId: audioInputDeviceId,
      );
      if (audioOutputDeviceId != null && audioOutputDeviceId.isNotEmpty) {
        await _webrtc.setAudioOutput(audioOutputDeviceId);
      }

      _remoteStreamSub = _webrtc.onRemoteStream.listen((_) {
        notifyListeners();
      });

      _speakingSub = _webrtc.onSpeakingChanged.listen((states) {
        var changed = false;
        if (states.containsKey('local')) {
          final key = _userId ?? 'local';
          if (_speakingStates[key] != states['local']) {
            _speakingStates[key] = states['local']!;
            changed = true;
          }
        }
        if (states.containsKey('remote') && _remotePeerId != null) {
          if (_speakingStates[_remotePeerId!] != states['remote']) {
            _speakingStates[_remotePeerId!] = states['remote']!;
            changed = true;
          }
        }
        if (changed) notifyListeners();
      });
    } catch (e) {
      debugPrint('[CallProvider] handoffJoin: Failed to open media: $e');
    }

    if (_userId != null) {
      await WireGuardService.instance.init(_userId!);
    }

    if (_serverUrl != null && _jwtToken != null) {
      _listenToSignaling();
      _listenToSignalingState();
      // isHandoff: true → server connects with ?handoff=true.
      _signaling.connect(
        _serverUrl!,
        jwtToken: _jwtToken!,
        roomId: channelId,
        isHandoff: true,
      );
    }

    debugPrint('[CallProvider] Handoff join on channel: $channelId');
    notifyListeners();
  }

  /// Leave the current call.
  Future<void> leaveCall() async {
    // Notify the server we're leaving.
    if (_signaling.state == SignalingState.connected) {
      _signaling.send(const SignalingMessage(type: SignalType.leave));
    }

    _messageSub?.cancel();
    _messageSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _remoteStreamSub?.cancel();
    _remoteStreamSub = null;
    _speakingSub?.cancel();
    _speakingSub = null;

    _speakingStates.clear();
    _roomMembers.clear();
    _peerNames.clear();

    await _webrtc.closePeerConnection();
    _signaling.disconnect();
    await WireGuardService.instance.stopTunnel();

    _isInCall = false;
    _currentChannelId = null;
    _remotePeerId = null;
    _peerConnectionReady = false;
    _pendingOffer = false;
    _pendingIncomingOffer = null;
    _pendingIceCandidates.clear();
    notifyListeners();

    debugPrint('[CallProvider] Left call');
  }

  /// Initiate a call to a specific peer (creates and sends an offer).
  Future<void> callPeer(String peerId) async {
    _remotePeerId = peerId;
    await _webrtc.createOffer();
    debugPrint('[CallProvider] Calling peer: $peerId');
  }

  // ── Media Forwarding ──

  /// Toggle mic on the actual WebRTC track.
  void setMicEnabled(bool enabled) {
    _webrtc.setMicEnabled(enabled);
  }

  /// Toggle camera on the actual WebRTC track.
  void setCameraEnabled(bool enabled) {
    _webrtc.setCameraEnabled(enabled);
  }

  /// Hot-swap audio processing constraints (EC / NS / AGC / profile) without
  /// dropping the call. Mirrors the same-named method on [WebRTCService].
  Future<void> updateAudioConstraints(
    MediaQualitySettings settings, {
    String? audioInputDeviceId,
  }) async {
    await _webrtc.updateAudioConstraints(
      settings,
      audioInputDeviceId: audioInputDeviceId,
    );
  }

  /// Apply native C++ audio processing matching the given voice profile.
  Future<void> setMicVoiceProfile(AudioInputProfile profile) async {
    await _webrtc.setMicVoiceProfile(profile);
  }

  /// Hot-swap the audio input device without dropping the call.
  Future<void> updateAudioInputDevice(String deviceId) async {
    await _webrtc.updateAudioInput(deviceId);
  }

  /// Change the audio output device (speakers/headphones).
  Future<void> setAudioOutputDevice(String deviceId) async {
    await _webrtc.setAudioOutput(deviceId);
  }

  // ── Screen Share ──

  /// Start screen capture and replace camera/mic tracks on the peer connection.
  ///
  /// [source] is the [DesktopCapturerSource] chosen by the user in the picker
  /// dialog.  Required on Windows/Linux/macOS; may be null on Web.
  Future<void> startScreenShare(
    MediaQualitySettings settings,
    DesktopCapturerSource? source, {
    bool shareAudio = false,
  }) async {
    await _webrtc.startScreenShare(settings, source, shareAudio: shareAudio);
    notifyListeners();
  }

  /// Stop screen capture and restore camera/mic tracks.
  Future<void> stopScreenShare() async {
    await _webrtc.stopScreenShare();
    notifyListeners();
  }

  // ── Mic preview ──

  /// Start independent mic level polling for the audio settings panel.
  /// No-op when the user is already in an active call.
  Future<void> startMicPreview() => _webrtc.startMicPreview();

  /// Stop the mic level preview and release its resources.
  Future<void> stopMicPreview() => _webrtc.stopMicPreview();

  // ── Chat ──

  /// Send a chat message to the current room via signaling.
  /// Only works when connected; returns false if not connected.
  bool sendChatMessage({
    required String channelId,
    required String content,
    required String senderName,
  }) {
    if (_signaling.state != SignalingState.connected) return false;
    _signaling.send(
      SignalingMessage(
        type: SignalType.chat,
        payload: {
          'channel_id': channelId,
          'content': content,
          'sender_name': senderName,
        },
      ),
    );
    return true;
  }

  /// Send a soundboard effect to the room via the chat broadcast mechanism.
  bool sendSoundboardEffect(String effectName) {
    if (_signaling.state != SignalingState.connected || !_isInCall) {
      return false;
    }
    _signaling.send(
      SignalingMessage(
        type: SignalType.chat,
        payload: {'type': 'soundboard', 'effect': effectName},
      ),
    );
    return true;
  }

  /// Listen for signaling connection state.
  ///
  /// On every successful connection (including reconnects after transient
  /// network errors) we re-send the `wg_announce` so the server always has
  /// up-to-date WireGuard identity for this client.
  void _listenToSignalingState() {
    _stateSub?.cancel();
    _stateSub = _signaling.onState.listen((state) {
      if (state == SignalingState.connected && _currentChannelId != null) {
        debugPrint(
          '[CallProvider] Signaling connected for channel: $_currentChannelId',
        );
        final wg = WireGuardService.instance;
        if (wg.isInitialized) {
          _signaling.send(
            SignalingMessage(
              type: SignalType.wgAnnounce,
              payload: {
                'wg_pub_key': wg.publicKey!,
                'virtual_ip': wg.virtualIP!,
                'public_endpoint': wg.publicEndpoint!,
              },
            ),
          );
          debugPrint('[CallProvider] wg_announce sent');
        }
      }
      notifyListeners();
    });
  }

  /// Listen to incoming signaling messages and route to WebRTC.
  void _listenToSignaling() {
    _messageSub?.cancel();
    _messageSub = _signaling.onMessage.listen((message) async {
      switch (message.type) {
        // ── room_state: server snapshot sent to us when we first join ──────────
        // The Go server broadcasts user_join only to EXISTING peers; we never
        // receive our own user_join.  Instead we learn about existing peers here
        // and use the same compareTo tiebreaker to decide who offers.
        //
        //  _userId < member  →  we are the offerer  (initiate)
        //  _userId > member  →  we are the answerer (wait for their offer)
        case SignalType.roomState:
          final rawMembers = message.payload['members'] as List<dynamic>? ?? [];
          // Rebuild member list from server snapshot (includes self).
          _roomMembers.clear();
          if (_userId != null) _roomMembers.add(_userId!);
          for (final raw in rawMembers) {
            final m = raw as Map<String, dynamic>;
            final memberId = m['user_id'] as String?;
            if (memberId == null || memberId == _userId) continue;
            if (!_roomMembers.contains(memberId)) _roomMembers.add(memberId);
            // Store display name if server provided it.
            final memberName = m['username'] as String?;
            if (memberName != null && memberName.isNotEmpty) {
              _peerNames[memberId] = memberName;
            }

            _remotePeerId = memberId;
            _webrtc.remotePeerId = memberId;

            final weOffer = _userId != null && _userId!.compareTo(memberId) < 0;
            if (_peerConnectionReady) {
              if (weOffer) {
                await _webrtc.createOffer();
                debugPrint(
                  '[CallProvider] Created offer for $memberId (room_state, we are offerer)',
                );
              } else {
                debugPrint(
                  '[CallProvider] Waiting for offer from $memberId (room_state, we are polite)',
                );
              }
            } else {
              _pendingOffer = true;
              _pendingShouldOffer = weOffer;
              debugPrint(
                '[CallProvider] Deferred offer decision for $memberId (room_state, PC not ready)',
              );
            }
          }
          break;

        // A new peer joined the room AFTER us.  The Go server won't echo this
        // back to the joining client, so message.from is always a remote peer.
        case SignalType.join:
          debugPrint('[CallProvider] Peer joined: ${message.from}');
          _remotePeerId = message.from;
          _webrtc.remotePeerId = message.from;
          if (message.from != null && !_roomMembers.contains(message.from!)) {
            _roomMembers.add(message.from!);
          }
          final joinUsername = message.payload['username'] as String?;
          if (message.from != null &&
              joinUsername != null &&
              joinUsername.isNotEmpty) {
            _peerNames[message.from!] = joinUsername;
          }
          // Do NOT attempt WebRTC negotiation here. The subsequent wg_peer_update
          // will restart the WireGuard tunnel; we must wait for it to settle
          // before ICE candidate gathering (see wgPeerUpdate handler below).
          // Store the offer decision so wgPeerUpdate can pick it up.
          final joinWeOffer =
              _userId != null &&
              message.from != null &&
              _userId!.compareTo(message.from!) < 0;
          if (_peerConnectionReady) {
            // Reset the PC but keep local camera/mic alive.
            await _webrtc.resetPeerConnection();
            _peerConnectionReady = false;
            _webrtc.remotePeerId =
                message.from; // <-- ADD THIS LINE to restore the wiped ID
          }
          _pendingOffer = true;
          _pendingShouldOffer = joinWeOffer;
          notifyListeners();
          break;

        case SignalType.offer:
          debugPrint('[CallProvider] Received offer from: ${message.from}');
          _remotePeerId ??= message.from;
          _webrtc.remotePeerId = _remotePeerId;
          if (_peerConnectionReady) {
            await _webrtc.handleOffer(message.payload);
            for (final candidate in _pendingIceCandidates) {
              await _webrtc.addIceCandidate(candidate);
            }
            _pendingIceCandidates.clear();
          } else {
            _pendingIncomingOffer = message.payload;
            debugPrint('[CallProvider] Buffered incoming offer (PC not ready)');
          }
          notifyListeners();
          break;

        case SignalType.answer:
          debugPrint('[CallProvider] Received answer from: ${message.from}');
          await _webrtc.handleAnswer(message.payload);
          for (final candidate in _pendingIceCandidates) {
            await _webrtc.addIceCandidate(candidate);
          }
          _pendingIceCandidates.clear();
          notifyListeners();
          break;

        case SignalType.iceCandidate:
          if (_peerConnectionReady && _webrtc.hasRemoteDescription) {
            await _webrtc.addIceCandidate(message.payload);
          } else {
            _pendingIceCandidates.add(message.payload);
          }
          break;

        case SignalType.leave:
          _remotePeerId = null;
          _webrtc.remotePeerId = null; // <-- ADD THIS LINE
          _roomMembers.remove(message.from);
          _webrtc.clearRemoteStream();
          notifyListeners();
          break;

        case SignalType.chat:
          // Skip echo of our own messages — we already display them locally.
          if (message.from == _userId) break;

          // Check if this is a soundboard broadcast under the chat channel
          if (message.payload['type'] == 'soundboard') {
            final effectName = message.payload['effect'] as String?;
            if (effectName != null) {
              try {
                final effect = SoundEffect.values.firstWhere(
                  (e) => e.name == effectName,
                );
                SoundService.instance.playSoundboard(effect);
              } catch (_) {}
            }
            break; // Stop processing; this isn't a text chat
          }

          // Relay incoming chat message to the current channel.
          final chId =
              message.payload['channel_id'] as String? ??
              _currentChannelId ??
              '';
          final content = message.payload['content'] as String? ?? '';
          final senderName =
              (message.payload['sender_name'] as String?) ??
              message.from ??
              'Unknown';
          if (content.isNotEmpty && !_chatController.isClosed) {
            _chatController.add((
              channelId: chId,
              message: ChatMessage(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                senderId: message.from ?? 'unknown',
                senderName: senderName,
                content: content,
                timestamp: DateTime.now(),
              ),
            ));
          }
          break;

        case SignalType.wgPeerUpdate:
          final peers = message.payload['peers'] as List<dynamic>? ?? [];
          await WireGuardService.instance.updatePeers(peers);

          for (final p in peers) {
            final pm = p as Map<String, dynamic>;
            final uid = pm['user_id'] as String?;
            if (uid != null && uid != _userId) {
              _peerNames[uid] = pm['username'] as String? ?? '';
            }
          }

          // Unconditionally wait for the OS to bind the new WireGuard VPN IP
          // before ICE candidate gathering. This covers both:
          //   - first connect (PC not yet ready)
          //   - existing peer's PC when a new peer joins and the tunnel restarts
          await Future<void>.delayed(const Duration(milliseconds: 2000));

          if (!_peerConnectionReady) {
            _webrtc.remotePeerId =
                _remotePeerId; // <-- ADD THIS LINE to guarantee it is never null during init
            await _webrtc.initPeerConnection();
            _peerConnectionReady = true;

            if (_pendingIncomingOffer != null) {
              await _webrtc.handleOffer(_pendingIncomingOffer!);
              _pendingIncomingOffer = null;
            } else if (_pendingOffer && _pendingShouldOffer) {
              await _webrtc.createOffer();
            }
            _pendingOffer = false;

            for (final candidate in _pendingIceCandidates) {
              await _webrtc.addIceCandidate(candidate);
            }
            _pendingIceCandidates.clear();
          } else {
            // PC already ready: a new peer joined. Renegotiate if we are
            // the alphabetically-lower peer (offerer role).
            if (_userId != null &&
                _remotePeerId != null &&
                _userId!.compareTo(_remotePeerId!) < 0) {
              _webrtc.remotePeerId =
                  _remotePeerId; // ensure it is set for routing
              await _webrtc.createOffer();
            }
          }
          notifyListeners();
          break;

        case SignalType.wgAnnounce: // outbound-only; server never sends this
        case SignalType.userList:
        case SignalType.error:
        case SignalType.handoffStart: // outbound-only; server never sends this
          break;

        // ── handoff_resume: a peer finished a handoff and reconnected ────────
        // Their old PeerConnection is gone. Clear our remote state and
        // re-negotiate just as we would for a fresh user_join, but without
        // triggering a UI "user left / rejoined" notification.
        case SignalType.handoffResume:
          debugPrint('[CallProvider] Peer handoff resumed: ${message.from}');
          _remotePeerId = message.from;
          _webrtc.remotePeerId = message.from;
          if (message.from != null && !_roomMembers.contains(message.from!)) {
            _roomMembers.add(message.from!);
          }
          notifyListeners();
          // Tiebreaker offer: alphabetically-lower userId initiates.
          final weOfferHandoff =
              _userId != null &&
              message.from != null &&
              _userId!.compareTo(message.from!) < 0;
          if (_peerConnectionReady) {
            if (weOfferHandoff) {
              await _webrtc.createOffer();
              debugPrint(
                '[CallProvider] Created offer for ${message.from} (handoff_resume, we are offerer)',
              );
            }
          } else {
            _pendingOffer = true;
            _pendingShouldOffer = weOfferHandoff;
            debugPrint(
              '[CallProvider] Deferred offer for ${message.from} (handoff_resume, PC not ready)',
            );
          }
          break;
      }
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _stateSub?.cancel();
    _remoteStreamSub?.cancel();
    _speakingSub?.cancel();
    if (!_chatController.isClosed) _chatController.close();
    _webrtc.dispose();
    _signaling.dispose();
    super.dispose();
  }
}
