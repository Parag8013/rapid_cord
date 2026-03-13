import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/media_quality.dart';
import 'signaling_service.dart';

/// Configuration for ICE servers.
class IceServerConfig {
  static const Map<String, dynamic> defaultConfig = {
    'iceServers': [
      // ZeroTier direct — no STUN/TURN needed on the virtual LAN.
      // Add public STUN as fallback for non-ZeroTier scenarios.
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };
}

/// Manages the RTCPeerConnection lifecycle.
///
/// Handles:
/// - Creating peer connections with media constraints
/// - SDP offer/answer exchange via [SignalingService]
/// - ICE candidate trickle
/// - Local/remote MediaStream management
/// - Bandwidth and quality controls via RTCRtpSender
/// - Screen share (replaces camera/mic tracks with display media)
/// - Speaking detection via periodic stats polling
class WebRTCService {
  final SignalingService _signaling;
  RTCPeerConnection? _peerConnection;
  MediaQualitySettings _qualitySettings = const MediaQualitySettings();

  // ── Camera/mic media ───────────────────────────────────────────────────────
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _renderersInitialized = false;

  // ── Screen share ─────────────────────────────────────────────────────────
  MediaStream? _screenStream;
  RTCVideoRenderer screenRenderer = RTCVideoRenderer();
  bool _screenRendererInitialized = false;
  bool _isScreenSharing = false;
  bool get isScreenSharing => _isScreenSharing;
  // Senders for the added screen tracks — kept so we can removeTrack them.
  RTCRtpSender? _screenVideoSender;
  RTCRtpSender? _screenAudioSender;
  // Sender and track for the Windows WASAPI system-audio loopback source.
  // Kept separate from _screenAudioSender (which is display-media audio) so
  // both can coexist and each can be individually torn down.
  RTCRtpSender? _systemAudioSender;
  MediaStreamTrack? _systemAudioTrack;
  // Remote peer's screen share stream + renderer.
  MediaStream? _remoteScreenStream;
  RTCVideoRenderer remoteScreenRenderer = RTCVideoRenderer();

  // ── Mic preview (independent of peer connection) ──────────────────────
  // Used by AudioSettingsPanel so the amplitude bar works even when the user
  // is not currently in a call (no RTCPeerConnection exists yet).
  RTCPeerConnection? _micPreviewPc;
  MediaStream? _micPreviewStream; // non-null only when we own the stream
  Timer? _micPreviewTimer;

  // ── Speaking detection ─────────────────────────────────────────────────
  Timer? _speakingTimer;
  final _speakingController = StreamController<Map<String, bool>>.broadcast();
  final _localAudioLevelController = StreamController<double>.broadcast();
  final _speakingStates = <String, bool>{};
  Stream<Map<String, bool>> get onSpeakingChanged => _speakingController.stream;
  Stream<double> get onLocalAudioLevelChanged =>
      _localAudioLevelController.stream;

  // ── Other streams ─────────────────────────────────────────────────────
  StreamController<MediaStream> _remoteStreamController =
      StreamController<MediaStream>.broadcast();
  StreamController<RTCPeerConnectionState> _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();

  Stream<MediaStream> get onRemoteStream => _remoteStreamController.stream;
  Stream<RTCPeerConnectionState> get onConnectionState =>
      _connectionStateController.stream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  MediaQualitySettings get qualitySettings => _qualitySettings;
  bool _hasRemoteDescription = false;
  bool get hasRemoteDescription => _hasRemoteDescription;

  /// The remote peer's ID — set by CallProvider so outgoing messages
  /// include `target_id` for the server to relay correctly.
  String? remotePeerId;

  WebRTCService(this._signaling);

  /// Initialize the video renderers.
  Future<void> initialize() async {
    if (_renderersInitialized) return;
    localRenderer = RTCVideoRenderer();
    remoteRenderer = RTCVideoRenderer();
    screenRenderer = RTCVideoRenderer();
    remoteScreenRenderer = RTCVideoRenderer();
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    await screenRenderer.initialize();
    await remoteScreenRenderer.initialize();
    _renderersInitialized = true;
    _screenRendererInitialized = true;

    // Recreate stream controllers if previously closed.
    if (_remoteStreamController.isClosed) {
      _remoteStreamController = StreamController<MediaStream>.broadcast();
    }
    if (_connectionStateController.isClosed) {
      _connectionStateController =
          StreamController<RTCPeerConnectionState>.broadcast();
    }
  }

  /// Open local media (camera + mic) with quality settings.
  ///
  /// Applies video resolution from [settings] to `getUserMedia` constraints.
  /// Falls back to the service's current [_qualitySettings] if none provided.
  Future<MediaStream> openUserMedia({
    bool video = true,
    bool audio = true,
    MediaQualitySettings? settings,
    String? audioInputDeviceId,
  }) async {
    final qs = settings ?? _qualitySettings;
    _qualitySettings = qs;

    dynamic audioParams = audio
        ? Map<String, dynamic>.from(qs.audioConstraints)
        : false;
    if (audioParams is Map<String, dynamic> &&
        audioInputDeviceId != null &&
        audioInputDeviceId.isNotEmpty) {
      audioParams['deviceId'] = {'exact': audioInputDeviceId};
    }

    final constraints = <String, dynamic>{
      'audio': audioParams,
      'video': video ? qs.videoConstraints : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    if (audio) _triggerDuckingOptOut();
    localRenderer.srcObject = _localStream;
    return _localStream!;
  }

  Future<void> initPeerConnection() async {
    if (_peerConnection != null) return;

    // The real PC is ready — shut down any preview-only PC so there is only
    // one source emitting on _localAudioLevelController.
    await stopMicPreview();

    _peerConnection = await createPeerConnection(IceServerConfig.defaultConfig);

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }
    }

    // Re-attach screen share tracks if they exist, so the stream continues
    // for remaining or new peers after a renegotiation.
    if (_isScreenSharing && _screenStream != null) {
      if (_screenStream!.getVideoTracks().isNotEmpty) {
        _screenVideoSender = await _peerConnection!.addTrack(
          _screenStream!.getVideoTracks().first,
          _screenStream!,
        );
      }
      if (_screenStream!.getAudioTracks().isNotEmpty) {
        _screenAudioSender = await _peerConnection!.addTrack(
          _screenStream!.getAudioTracks().first,
          _screenStream!,
        );
      }
      // Re-attach the system-audio loopback track (Windows only) if it was
      // active during the previous connection. The WasapiLoopbackCapturer
      // keeps running across PC resets, so the track itself is still live.
      if (_systemAudioTrack != null) {
        _systemAudioSender = await _peerConnection!.addTrack(
          _systemAudioTrack!,
          _screenStream!,
        );
      }
    }
    await applyBitrateConstraints();

    _peerConnection!.onTrack = (RTCTrackEvent event) {
      // Identify the stream this track belongs to. Some implementations omit
      // the streams list during renegotiation — fall back to creating a
      // synthetic key from the track kind so audio/video stay separated.
      final stream = event.streams.isNotEmpty ? event.streams.first : null;
      final streamId = stream?.id ?? 'remote_${event.track.kind}';

      if (_remoteStream == null || _remoteStream!.id == streamId) {
        // First (or same) stream: camera/mic from the remote peer.
        if (stream != null) {
          _remoteStream = stream;
          remoteRenderer.srcObject = _remoteStream;
        }
      } else {
        // Different stream ID: the remote peer is screen sharing.
        if (stream != null) {
          _remoteScreenStream = stream;
          remoteScreenRenderer.srcObject = _remoteScreenStream;
        }
      }
      final toNotify = stream ?? _remoteStream;
      if (toNotify != null) _remoteStreamController.add(toNotify);
    };

    _peerConnection!
        .onRemoveTrack = (MediaStream stream, MediaStreamTrack track) {
      if (_remoteScreenStream != null && stream.id == _remoteScreenStream!.id) {
        remoteScreenRenderer.srcObject = null;
        _remoteScreenStream = null;
        if (_remoteStream != null) _remoteStreamController.add(_remoteStream!);
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (remotePeerId == null) return;
      _signaling.send(
        SignalingMessage(
          type: SignalType.iceCandidate,
          to: remotePeerId,
          payload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };

    // Connection state monitoring.
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('[WebRTCService] Connection state: $state');
      _connectionStateController.add(state);
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('[WebRTCService] ICE connection state: $state');
    };

    _startSpeakingDetection();
  }

  /// Apply bitrate constraints to all RTCRtpSenders on the peer connection.
  ///
  /// Sets `maxBitrate` on encoding parameters for both audio and video senders.
  /// This is the recommended approach per the WebRTC spec — modifying sender
  /// parameters is cleaner than SDP munging and works across renegotiations.
  Future<void> applyBitrateConstraints([MediaQualitySettings? settings]) async {
    if (_peerConnection == null) return;

    final qs = settings ?? _qualitySettings;
    final senders = await _peerConnection!.getSenders();

    for (final sender in senders) {
      if (sender.track == null) continue;

      final params = sender.parameters;
      if (params.encodings == null || params.encodings!.isEmpty) {
        params.encodings = [RTCRtpEncoding()];
      }

      for (final encoding in params.encodings!) {
        if (sender.track!.kind == 'audio') {
          encoding.maxBitrate = qs.audioBitrate.bps;
        } else if (sender.track!.kind == 'video') {
          encoding.maxBitrate = qs.videoBitrate.bps;
        }
      }

      await sender.setParameters(params);
      debugPrint(
        '[WebRTCService] Applied bitrate for ${sender.track!.kind}: '
        '${sender.track!.kind == "audio" ? qs.audioBitrate.label : qs.videoBitrate.label}',
      );
    }
  }

  /// Update quality settings and apply them live.
  ///
  /// - Updates bitrate constraints on existing senders immediately.
  /// - If video resolution changed and we have an active local stream,
  ///   re-acquires media with the new resolution constraints.
  Future<void> updateQuality(MediaQualitySettings newSettings) async {
    final resolutionChanged =
        newSettings.videoResolution != _qualitySettings.videoResolution;
    _qualitySettings = newSettings;

    // Apply bitrate constraints immediately (no renegotiation needed).
    await applyBitrateConstraints(newSettings);

    // If resolution changed, re-acquire media.
    if (resolutionChanged && _localStream != null) {
      debugPrint(
        '[WebRTCService] Resolution changed to ${newSettings.videoResolution.label}, re-acquiring media',
      );
      // Stop old video tracks.
      for (final track in _localStream!.getVideoTracks()) {
        track.stop();
      }

      // Get new stream with updated constraints.
      final newStream = await navigator.mediaDevices.getUserMedia({
        'audio': false, // Keep existing audio.
        'video': newSettings.videoConstraints,
      });

      // Replace video track on the peer connection sender.
      if (_peerConnection != null && newStream.getVideoTracks().isNotEmpty) {
        final newVideoTrack = newStream.getVideoTracks().first;
        final senders = await _peerConnection!.getSenders();
        for (final sender in senders) {
          if (sender.track?.kind == 'video') {
            await sender.replaceTrack(newVideoTrack);
            break;
          }
        }

        // Update local stream and renderer.
        _localStream!.removeTrack(_localStream!.getVideoTracks().first);
        _localStream!.addTrack(newVideoTrack);
        localRenderer.srcObject = _localStream;
      }

      // Re-apply bitrate after track replacement.
      await applyBitrateConstraints(newSettings);
    }
  }

  /// Hot-swap the local microphone to a new device without dropping the call.
  Future<void> updateAudioInput(String deviceId) async {
    if (_localStream == null) return;

    final qs = _qualitySettings;
    final audioParams = Map<String, dynamic>.from(qs.audioConstraints);
    audioParams['deviceId'] = {'exact': deviceId};

    try {
      final newStream = await navigator.mediaDevices.getUserMedia({
        'audio': audioParams,
        'video': false,
      });

      if (newStream.getAudioTracks().isNotEmpty) {
        final newAudioTrack = newStream.getAudioTracks().first;
        if (_peerConnection != null) {
          final senders = await _peerConnection!.getSenders();
          final oldAudioId = _localStream!.getAudioTracks().first.id;
          for (final sender in senders) {
            if (sender.track?.kind == 'audio' &&
                sender.track?.id == oldAudioId) {
              await sender.replaceTrack(newAudioTrack);
              break;
            }
          }
        }

        final oldAudioTrack = _localStream!.getAudioTracks().first;
        _localStream!.removeTrack(oldAudioTrack);
        oldAudioTrack.stop();
        _localStream!.addTrack(newAudioTrack);
        debugPrint(
          '[WebRTCService] Successfully swapped audio input to $deviceId',
        );
      }
    } catch (e) {
      debugPrint('[WebRTCService] Failed to swap audio input: $e');
    }
  }

  /// Hot-swap audio processing constraints (EC / NS / AGC profile change)
  /// without dropping the call. Re-acquires the mic with the new constraints
  /// and replaces the sender track on the peer connection.
  Future<void> updateAudioConstraints(
    MediaQualitySettings settings, {
    String? audioInputDeviceId,
  }) async {
    _qualitySettings = settings;
    if (_localStream == null) return;

    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isEmpty) return;

    final audioParams = Map<String, dynamic>.from(settings.audioConstraints);
    if (audioInputDeviceId != null && audioInputDeviceId.isNotEmpty) {
      audioParams['deviceId'] = {'exact': audioInputDeviceId};
    }

    try {
      final newStream = await navigator.mediaDevices.getUserMedia({
        'audio': audioParams,
        'video': false,
      });
      _triggerDuckingOptOut();
      if (newStream.getAudioTracks().isEmpty) return;
      final newAudioTrack = newStream.getAudioTracks().first;

      if (_peerConnection != null) {
        final senders = await _peerConnection!.getSenders();
        final oldId = audioTracks.first.id;
        for (final sender in senders) {
          if (sender.track?.kind == 'audio' && sender.track?.id == oldId) {
            await sender.replaceTrack(newAudioTrack);
            break;
          }
        }
      }

      final oldTrack = audioTracks.first;
      _localStream!.removeTrack(oldTrack);
      await oldTrack.stop();
      _localStream!.addTrack(newAudioTrack);
      debugPrint(
        '[WebRTCService] Audio constraints updated: ${settings.audioConstraints}',
      );
    } catch (e) {
      debugPrint('[WebRTCService] Failed to update audio constraints: $e');
    }
  }

  /// Tells the Windows audio engine to opt every live audio session out of the
  /// Communications ducking policy. Fires immediately and again after 400 ms
  /// to cover the ADM's deferred IAudioClient::Start() call.
  void _triggerDuckingOptOut() {
    if (!WebRTC.platformIsWindows) return;
    WebRTC.invokeMethod<void, void>('disableAudioDucking').ignore();
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      WebRTC.invokeMethod<void, void>('disableAudioDucking').ignore();
    });
  }

  /// Sets the Windows Communications Ducking level.
  ///
  /// Writes the preference to the Windows registry
  /// (HKCU\Software\Microsoft\Multimedia\Audio → UserDuckingPreference).
  ///
  /// [level]: 0 = mute all, 1 = reduce 80%, 2 = reduce 50%, 3 = do nothing
  static void setWindowsDuckingLevel(int level) {
    if (!WebRTC.platformIsWindows) return;
    WebRTC.invokeMethod<void, int>('setDuckingLevel', level).ignore();
  }

  /// Apply native C++ audio processing that matches [profile].
  ///
  /// Maps each [AudioInputProfile] to noise-gate / RNNoise settings and sends
  /// them to the C++ `MicCaptureProcessor` via the `setMicProcessing` channel.
  Future<void> setMicVoiceProfile(AudioInputProfile profile) async {
    try {
      switch (profile) {
        case AudioInputProfile.voiceIsolation:
          // Built-in WebRTC NS + RNNoise neural denoiser (if available).
          await MediaDevices.setMicProcessing(
            noiseGate: false,
            threshold: 0.01,
            rnnoise: true,
          );
        case AudioInputProfile.studio:
          // Flat pass-through — disable all custom processing.
          await MediaDevices.setMicProcessing(
            noiseGate: false,
            threshold: 0.01,
            rnnoise: false,
          );
        case AudioInputProfile.custom:
          // Noise gate only: a lightweight amplitude gate replaces the
          // built-in suppressor when the user enables custom mode.
          await MediaDevices.setMicProcessing(
            noiseGate: true,
            threshold: 0.015,
            rnnoise: false,
          );
      }
      debugPrint('[WebRTCService] setMicVoiceProfile: $profile');
    } catch (e) {
      debugPrint('[WebRTCService] setMicVoiceProfile failed: $e');
    }
  }

  /// Change the audio output device (speakers/headphones) for remote streams.
  Future<void> setAudioOutput(String deviceId) async {
    try {
      await remoteRenderer.audioOutput(deviceId);
      await remoteScreenRenderer.audioOutput(deviceId);
      debugPrint('[WebRTCService] Successfully set audio output to $deviceId');
    } catch (e) {
      debugPrint('[WebRTCService] Failed to set audio output: $e');
    }
  }

  /// Create an SDP offer and send it via signaling.
  Future<void> createOffer() async {
    if (_peerConnection == null || remotePeerId == null) {
      debugPrint(
        '[WebRTCService] skipping createOffer — peerConnection or remotePeerId is null',
      );
      return;
    }

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);

    // Debug: log the SDP so we can verify m=audio lines for all tracks.
    // Look for multiple m=audio sections — one for mic, one for screen share.
    if (offer.sdp != null) {
      final audioLines = offer.sdp!
          .split('\n')
          .where(
            (l) =>
                l.startsWith('m=audio') ||
                l.startsWith('a=mid') ||
                l.startsWith('a=msid'),
          )
          .toList();
      debugPrint('[WebRTCService] SDP audio sections: $audioLines');
    }

    _signaling.send(
      SignalingMessage(
        type: SignalType.offer,
        to: remotePeerId,
        payload: {'sdp': offer.sdp, 'type': offer.type},
      ),
    );
    debugPrint('[WebRTCService] Sent offer to $remotePeerId');
  }

  /// Process an incoming SDP offer and send back an answer.
  ///
  /// Implements "polite peer" collision handling:
  /// If we already have a local offer, we rollback ours first.
  Future<void> handleOffer(Map<String, dynamic> sdpData) async {
    if (_peerConnection == null) {
      debugPrint('[WebRTCService] No peer connection for offer — creating one');
      await initPeerConnection();
    }

    // Debug: log what we actually received.
    debugPrint('[WebRTCService] Offer payload keys: ${sdpData.keys.toList()}');
    debugPrint(
      '[WebRTCService] Offer sdp present: ${sdpData['sdp'] != null}, type: ${sdpData['type']}',
    );

    final sdp = sdpData['sdp'] as String?;
    final type = sdpData['type'] as String?;

    if (sdp == null || sdp.isEmpty || type == null) {
      debugPrint('[WebRTCService] Invalid offer — sdp or type is null/empty');
      return;
    }

    // Handle offer collision: if we already sent an offer (have-local-offer),
    // rollback our local description before setting the remote offer.
    final signalingState = _peerConnection!.signalingState;
    if (signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint(
        '[WebRTCService] Offer collision detected — rolling back local offer',
      );
      await _peerConnection!.setLocalDescription(
        RTCSessionDescription('', 'rollback'),
      );
    }

    debugPrint('[WebRTCService] Setting remote description (offer)');
    final description = RTCSessionDescription(sdp, type);
    await _peerConnection!.setRemoteDescription(description);
    _hasRemoteDescription = true;

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    _signaling.send(
      SignalingMessage(
        type: SignalType.answer,
        to: remotePeerId,
        payload: {'sdp': answer.sdp, 'type': answer.type},
      ),
    );
    debugPrint('[WebRTCService] Sent answer to $remotePeerId');
  }

  /// Process an incoming SDP answer.
  Future<void> handleAnswer(Map<String, dynamic> sdpData) async {
    if (_peerConnection == null) return;

    debugPrint('[WebRTCService] Answer payload keys: ${sdpData.keys.toList()}');

    final sdp = sdpData['sdp'] as String?;
    final type = sdpData['type'] as String?;

    if (sdp == null || sdp.isEmpty || type == null) {
      debugPrint('[WebRTCService] Invalid answer — sdp or type is null/empty');
      return;
    }

    // Only accept answer if we're in have-local-offer state.
    final signalingState = _peerConnection!.signalingState;
    if (signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint(
        '[WebRTCService] Ignoring answer — not in have-local-offer state ($signalingState)',
      );
      return;
    }

    final description = RTCSessionDescription(sdp, type);
    await _peerConnection!.setRemoteDescription(description);
    _hasRemoteDescription = true;
    debugPrint('[WebRTCService] Remote description set (answer)');
  }

  /// Add a remote ICE candidate.
  Future<void> addIceCandidate(Map<String, dynamic> candidateData) async {
    if (_peerConnection == null) return;

    final candidate = RTCIceCandidate(
      candidateData['candidate'] as String?,
      candidateData['sdpMid'] as String?,
      candidateData['sdpMLineIndex'] as int?,
    );
    await _peerConnection!.addCandidate(candidate);
  }

  /// Toggle the microphone on/off.
  void setMicEnabled(bool enabled) {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = enabled;
    });
  }

  /// Toggle the camera on/off.
  void setCameraEnabled(bool enabled) {
    _localStream?.getVideoTracks().forEach((track) {
      track.enabled = enabled;
    });
  }

  /// Close only the RTCPeerConnection and clear remote media state,
  /// keeping local camera/mic streams alive for reconnection.
  ///
  /// Call this when resetting for a new peer (join handler) or when the
  /// remote peer leaves.  [localRenderer] and [_localStream] are untouched,
  /// so the user's own camera tile stays visible.
  Future<void> resetPeerConnection() async {
    _stopSpeakingDetection();
    _speakingStates.clear();

    // Stop screen share tracks locally — NO. Do not stop screen tracks here.
    // We want the screen share to persist for the host even when a peer leaves.
    // The senders will be garbage collected with the PC. We will reattach the
    // _screenStream tracks in initPeerConnection when the next peer connects.
    // _systemAudioTrack is also kept alive so the capturer continues running.
    _screenVideoSender = null;
    _screenAudioSender = null;
    _systemAudioSender = null;

    try {
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    try {
      _remoteScreenStream?.dispose();
    } catch (_) {}
    _remoteScreenStream = null;

    if (_renderersInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        remoteRenderer.srcObject = null;
        remoteScreenRenderer.srcObject = null;
      });
    }

    final pc = _peerConnection;
    _peerConnection = null;
    remotePeerId = null;
    _hasRemoteDescription = false;
    if (pc != null) {
      try {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          try {
            await pc.removeTrack(sender);
          } catch (_) {}
        }
        await pc.close();
      } catch (e) {
        debugPrint('[WebRTCService] resetPeerConnection: $e');
      }
    }
  }

  /// Close the peer connection AND stop all local media tracks.
  /// Renderers stay alive so the service can be reused for the next call.
  Future<void> closePeerConnection() async {
    _stopSpeakingDetection();
    _speakingStates.clear();
    if (_isScreenSharing) await stopScreenShare();

    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localStream = null;

    try {
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;

    try {
      _remoteScreenStream?.dispose();
    } catch (_) {}
    _remoteScreenStream = null;

    // Guard against uninitialised renderers (e.g. init failed in pop-out).
    // Defer to the next frame to avoid "!debugNeedsLayout" assertion.
    if (_renderersInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        localRenderer.srcObject = null;
        remoteRenderer.srcObject = null;
        remoteScreenRenderer.srcObject = null;
      });
    }

    _screenVideoSender = null;
    _screenAudioSender = null;
    final pc = _peerConnection;
    _peerConnection = null;
    remotePeerId = null;
    _hasRemoteDescription = false;
    if (pc != null) {
      try {
        final senders = await pc.getSenders();
        for (final sender in senders) {
          try {
            await pc.removeTrack(sender);
          } catch (_) {}
        }
        await pc.close();
      } catch (e) {
        debugPrint('[WebRTCService] closePeerConnection: $e');
      }
    }
  }

  // ── Screen Share ────────────────────────────────────────────────────────────

  /// Capture the display (+ system audio if the OS allows) and replace the
  /// camera/mic tracks on the active peer connection.
  ///
  /// On Windows/Linux/macOS [source] must be a [DesktopCapturerSource] obtained
  /// via desktopCapturer.getSources().  On Web [source] may be null (the
  /// browser shows its own picker).
  Future<void> startScreenShare(
    MediaQualitySettings settings,
    DesktopCapturerSource? source, {
    bool shareAudio = false,
  }) async {
    if (_isScreenSharing || _peerConnection == null) return;

    // CRITICAL: Always force audio:false in getDisplayMedia constraints.
    // We never want the default engine audio track. Our custom WASAPI track
    // below must be the ONLY audio track (Track 0) on this stream, otherwise
    // the remote WebRTC engine will play the default track and ignore ours.
    final Map<String, dynamic> constraints = source != null
        ? {
            'video': {
              'deviceId': {'exact': source.id},
              'mandatory': {'frameRate': settings.frameRate.value.toDouble()},
            },
            'audio': false,
          }
        : {'video': settings.screenConstraints['video'], 'audio': false};

    try {
      _screenStream = await navigator.mediaDevices.getDisplayMedia(constraints);
    } catch (e) {
      debugPrint('[WebRTCService] getDisplayMedia failed: $e');
      rethrow;
    }

    _isScreenSharing = true;
    screenRenderer.srcObject = _screenStream;

    // 1. ADD SCREEN VIDEO TRACK
    if (_screenStream!.getVideoTracks().isNotEmpty) {
      _screenVideoSender = await _peerConnection!.addTrack(
        _screenStream!.getVideoTracks().first,
        _screenStream!,
      );
      _screenStream!.getVideoTracks().first.onEnded = stopScreenShare;
    }

    // NOTE: We intentionally do NOT add _screenStream!.getAudioTracks() here.
    // Because audio:false is set above, there should be none. If the OS
    // ignores our constraint and provides one anyway, we skip it so our
    // custom WASAPI track remains Track 0.

    // 2. ADD CUSTOM WASAPI SYSTEM AUDIO TRACK (only audio track on stream)
    if (shareAudio) {
      try {
        // ADM BOOTSTRAP: The WebRTC Audio Device Module must be recording
        // before the custom source's CaptureFrame can reach the encoder.
        // getUserMedia(audio) is the standard way to kickstart the ADM.
        // If the user already has a mic stream (_localStream != null), the ADM
        // is already running and this is a no-op. Otherwise, open a short
        // bootstrap stream, add its track (so the ADM latches to the encoder),
        // then immediately close it — the custom WASAPI track takes over.
        if (_localStream == null) {
          debugPrint('[WebRTCService] Bootstrapping ADM for system audio...');
          try {
            final bootstrap = await navigator.mediaDevices.getUserMedia({
              'audio': {
                'mandatory': {'googDucking': 'false'},
              },
              'video': false,
            });
            _triggerDuckingOptOut();
            // Don't add the bootstrap tracks to the peer connection;
            // just opening getUserMedia starts the ADM recording loop.
            // Stop immediately — we only needed the ADM handshake.
            for (final t in bootstrap.getTracks()) {
              t.stop();
            }
            await bootstrap.dispose();
          } catch (e) {
            debugPrint('[WebRTCService] ADM bootstrap failed (non-fatal): $e');
          }
        }

        _systemAudioTrack = await MediaDevices.getSystemAudioTrack();
        _systemAudioSender = await _peerConnection!.addTrack(
          _systemAudioTrack!,
          _screenStream!,
        );
        debugPrint(
          '[WebRTCService] System audio (WASAPI loopback) track added as Track 0',
        );
      } catch (e) {
        debugPrint('[WebRTCService] System audio unavailable: $e');
        _systemAudioTrack = null;
        _systemAudioSender = null;
      }
    }

    // Renegotiate to advertise the new tracks to the remote peer.
    await createOffer();
    debugPrint('[WebRTCService] Screen share started');
  }

  Future<void> stopScreenShare() async {
    if (!_isScreenSharing) return;
    _isScreenSharing = false;

    if (_peerConnection != null) {
      if (_screenVideoSender != null) {
        await _peerConnection!.removeTrack(_screenVideoSender!);
      }
      if (_screenAudioSender != null) {
        await _peerConnection!.removeTrack(_screenAudioSender!);
      }
      // Remove the WASAPI loopback sender. Its track is disposed separately
      // below so the WasapiLoopbackCapturer is stopped via trackDispose.
      if (_systemAudioSender != null) {
        try {
          await _peerConnection!.removeTrack(_systemAudioSender!);
        } catch (e) {
          debugPrint(
            '[WebRTCService] Failed to remove system audio sender: $e',
          );
        }
      }
    }
    _screenVideoSender = null;
    _screenAudioSender = null;
    _systemAudioSender = null;

    // Stop the WASAPI loopback track. This calls trackDispose on the native
    // side, which erases the SystemAudioBundle and stops the capturer thread.
    await _systemAudioTrack?.stop();
    _systemAudioTrack = null;

    _screenStream?.getTracks().forEach((t) => t.stop());
    _screenStream?.dispose();
    _screenStream = null;
    screenRenderer.srcObject = null;

    // Renegotiate removal.
    if (_peerConnection != null) await createOffer();
    debugPrint('[WebRTCService] Screen share stopped');
  }

  // ── Mic preview ──────────────────────────────────────────────────────────

  /// Open a lightweight loopback [RTCPeerConnection] backed by the microphone
  /// so that [onLocalAudioLevelChanged] emits levels even when the user is
  /// not in an active call.
  ///
  /// - If a real peer connection already exists the preview is skipped; the
  ///   existing [_startSpeakingDetection] timer will emit the levels instead.
  /// - If [_localStream] is already open (user joined but WireGuard hasn't
  ///   connected yet) its audio tracks are reused so no second mic capture is
  ///   opened.
  Future<void> startMicPreview() async {
    if (_micPreviewPc != null || _peerConnection != null) return;

    try {
      final bool openedOwnStream = _localStream == null;
      if (openedOwnStream) {
        _micPreviewStream = await navigator.mediaDevices.getUserMedia({
          'audio': {
            // 'mandatory': {'googDucking': 'false'},
          },
          'video': false,
        });
        _triggerDuckingOptOut();
      }
      final source = _localStream ?? _micPreviewStream!;

      _micPreviewPc = await createPeerConnection({
        'iceServers': [],
        'sdpSemantics': 'unified-plan',
      });

      for (final track in source.getAudioTracks()) {
        await _micPreviewPc!.addTrack(track, source);
      }

      // createOffer + setLocalDescription causes libwebrtc to start
      // pipeline-processing the track, which is required before the
      // 'media-source' stats report appears.
      final offer = await _micPreviewPc!.createOffer({
        'offerToReceiveAudio': false,
        'offerToReceiveVideo': false,
      });
      await _micPreviewPc!.setLocalDescription(offer);

      _micPreviewTimer = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        if (_micPreviewPc == null) return;
        try {
          final stats = await _micPreviewPc!.getStats();
          for (final report in stats) {
            if (report.type == 'media-source' &&
                report.values['kind'] == 'audio') {
              final level =
                  (report.values['audioLevel'] as num?)?.toDouble() ?? 0.0;
              if (!_localAudioLevelController.isClosed) {
                _localAudioLevelController.add(level);
              }
            }
          }
        } catch (_) {}
      });
      debugPrint('[WebRTCService] Mic preview started');
    } catch (e) {
      debugPrint('[WebRTCService] startMicPreview failed: $e');
      await stopMicPreview();
    }
  }

  /// Stop the mic preview and release its resources.
  Future<void> stopMicPreview() async {
    _micPreviewTimer?.cancel();
    _micPreviewTimer = null;
    // Only stop/dispose the stream if we opened it ourselves.
    if (_micPreviewStream != null) {
      _micPreviewStream!.getTracks().forEach((t) => t.stop());
      _micPreviewStream!.dispose();
      _micPreviewStream = null;
    }
    final pc = _micPreviewPc;
    _micPreviewPc = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
    }
    debugPrint('[WebRTCService] Mic preview stopped');
  }

  /// Clear all remote media state (called when the remote peer leaves).
  void clearRemoteStream() {
    try {
      _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    remoteRenderer.srcObject = null;

    try {
      _remoteScreenStream?.dispose();
    } catch (_) {}
    _remoteScreenStream = null;
    remoteScreenRenderer.srcObject = null;
  }

  // ── Speaking Detection ───────────────────────────────────────────────────────

  /// Poll WebRTC stats every 200 ms to detect speaking activity.
  ///
  /// Emits `{'local': bool, 'remote': bool}` whenever the state changes.
  /// The threshold of 0.008 (-42 dBFS) catches comfortable talking levels
  /// while ignoring background hiss.
  void _startSpeakingDetection() {
    _speakingTimer?.cancel();
    _speakingTimer = Timer.periodic(const Duration(milliseconds: 200), (
      _,
    ) async {
      if (_peerConnection == null) return;
      try {
        final stats = await _peerConnection!.getStats();
        final newStates = <String, bool>{};

        for (final report in stats) {
          // Local outbound audio level (Chromium / Windows WebRTC).
          if (report.type == 'media-source' &&
              report.values['kind'] == 'audio') {
            final level =
                (report.values['audioLevel'] as num?)?.toDouble() ?? 0.0;
            newStates['local'] = level > 0.008;
            if (!_localAudioLevelController.isClosed) {
              _localAudioLevelController.add(level);
            }
          }
          // Remote inbound audio level.
          if (report.type == 'inbound-rtp' &&
              report.values['kind'] == 'audio') {
            final level =
                (report.values['audioLevel'] as num?)?.toDouble() ?? 0.0;
            newStates['remote'] = level > 0.008;
          }
        }

        var changed = false;
        for (final entry in newStates.entries) {
          if (_speakingStates[entry.key] != entry.value) {
            _speakingStates[entry.key] = entry.value;
            changed = true;
          }
        }
        if (changed && !_speakingController.isClosed) {
          _speakingController.add(Map.from(_speakingStates));
        }
      } catch (_) {
        // getStats can throw before the connection is fully established.
      }
    });
  }

  void _stopSpeakingDetection() {
    _speakingTimer?.cancel();
    _speakingTimer = null;
    _speakingStates.clear();
  }

  /// Full teardown — disposes renderers and closes stream controllers.
  /// Only call this when the service will never be reused.
  Future<void> dispose() async {
    await stopMicPreview();
    await closePeerConnection();

    if (_renderersInitialized) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _renderersInitialized = false;
    }
    if (_screenRendererInitialized) {
      await screenRenderer.dispose();
      await remoteScreenRenderer.dispose();
      _screenRendererInitialized = false;
    }

    if (!_remoteStreamController.isClosed) {
      _remoteStreamController.close();
    }
    if (!_connectionStateController.isClosed) {
      _connectionStateController.close();
    }
    if (!_speakingController.isClosed) {
      _speakingController.close();
    }
    if (!_localAudioLevelController.isClosed) {
      _localAudioLevelController.close();
    }
  }
}

