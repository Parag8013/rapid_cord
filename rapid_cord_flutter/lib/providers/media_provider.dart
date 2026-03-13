import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/media_quality.dart';
import '../services/sound_service.dart';

/// Manages local media state (mute, deafen, camera, screen share),
/// media quality settings, and volume controls.
class MediaProvider extends ChangeNotifier {
  bool _isMuted = false;
  bool _isDeafened = false;
  bool _isCameraOn = false;
  bool _isScreenSharing = false;
  bool _isInVoiceChannel = false;

  // ── Device Selection ──
  String? _audioInputDeviceId;
  String? _audioOutputDeviceId;

  // ── Quality Settings ──
  MediaQualitySettings _qualitySettings = const MediaQualitySettings();

  // ── Volume Controls ──
  double _masterVolume = 1.0;
  double _inputVolume = 1.0;

  // ── System Audio Gate ──
  // Normalised RMS floor for the system-audio noise gate (0 = disabled).
  double _systemAudioGateThreshold = 0.0;
  final Map<String, double> _participantVolumes = {};
  final Map<String, bool> _participantMuted = {};

  // ── Getters ──
  bool get isMuted => _isMuted;
  bool get isDeafened => _isDeafened;
  bool get isCameraOn => _isCameraOn;
  bool get isScreenSharing => _isScreenSharing;

  /// Convenience getter — true when the effective audio profile enables NS.
  bool get isNoiseSuppression =>
      _qualitySettings.audioConstraints['noiseSuppression'] as bool? ?? true;
  bool get isInVoiceChannel => _isInVoiceChannel;
  String? get audioInputDeviceId => _audioInputDeviceId;
  String? get audioOutputDeviceId => _audioOutputDeviceId;
  MediaQualitySettings get qualitySettings => _qualitySettings;
  double get masterVolume => _masterVolume;
  double get inputVolume => _inputVolume;
  double get systemAudioGateThreshold => _systemAudioGateThreshold;
  Map<String, double> get participantVolumes =>
      Map.unmodifiable(_participantVolumes);
  Map<String, bool> get participantMuted => Map.unmodifiable(_participantMuted);

  /// Update the system-audio noise gate threshold and push it to native.
  /// [threshold] is normalised RMS in [0, 1].  0.0 disables the gate.
  Future<void> setSystemAudioGateThreshold(double threshold) async {
    _systemAudioGateThreshold = threshold;
    notifyListeners();
    await MediaDevices.setSystemAudioNoiseGate(threshold);
  }

  // ── Media Toggles ──
  void toggleMute() {
    _isMuted = !_isMuted;
    if (!_isMuted && _isDeafened) {
      _isDeafened = false;
    }
    notifyListeners();
  }

  void toggleDeafen() {
    _isDeafened = !_isDeafened;
    if (_isDeafened) {
      _isMuted = true;
    }
    notifyListeners();
  }

  void toggleCamera() {
    _isCameraOn = !_isCameraOn;
    notifyListeners();
  }

  void toggleScreenShare() {
    _isScreenSharing = !_isScreenSharing;
    // Play event sound.
    SoundService.instance.play(
      _isScreenSharing ? SoundEffect.screenShareOn : SoundEffect.screenShareOff,
    );
    notifyListeners();
  }

  void toggleNoiseSuppression() {
    // Convenience toggle: cycles to custom profile and flips NS flag.
    final qs = _qualitySettings;
    if (qs.audioInputProfile != AudioInputProfile.custom) {
      _qualitySettings = qs.copyWith(
        audioInputProfile: AudioInputProfile.custom,
        noiseSuppression: !qs.audioConstraints['noiseSuppression'],
      );
    } else {
      _qualitySettings = qs.copyWith(noiseSuppression: !qs.noiseSuppression);
    }
    notifyListeners();
  }

  void joinVoiceChannel() {
    _isInVoiceChannel = true;
    SoundService.instance.play(SoundEffect.channelJoin);
    notifyListeners();
  }

  // ── Audio processing settings ─────────────────────────────────────────────

  /// Switch to a preset profile. Returns the updated settings so the caller
  /// can immediately pass them to [CallProvider.updateAudioConstraints].
  MediaQualitySettings setAudioInputProfile(AudioInputProfile profile) {
    _qualitySettings = _qualitySettings.copyWith(audioInputProfile: profile);
    notifyListeners();
    return _qualitySettings;
  }

  MediaQualitySettings setEchoCancellation(bool value) {
    _qualitySettings = _qualitySettings.copyWith(
      audioInputProfile: AudioInputProfile.custom,
      echoCancellation: value,
    );
    notifyListeners();
    return _qualitySettings;
  }

  MediaQualitySettings setNoiseSuppression(bool value) {
    _qualitySettings = _qualitySettings.copyWith(
      audioInputProfile: AudioInputProfile.custom,
      noiseSuppression: value,
    );
    notifyListeners();
    return _qualitySettings;
  }

  MediaQualitySettings setAutoGainControl(bool value) {
    _qualitySettings = _qualitySettings.copyWith(
      audioInputProfile: AudioInputProfile.custom,
      autoGainControl: value,
    );
    notifyListeners();
    return _qualitySettings;
  }

  void setPushToTalk(bool enabled) {
    _qualitySettings = _qualitySettings.copyWith(pushToTalk: enabled);
    notifyListeners();
  }

  void setPushToTalkKey(String keyLabel) {
    _qualitySettings = _qualitySettings.copyWith(pushToTalkKey: keyLabel);
    notifyListeners();
  }

  void leaveVoiceChannel() {
    _isInVoiceChannel = false;
    _isCameraOn = false;
    _isScreenSharing = false;
    SoundService.instance.play(SoundEffect.channelLeave);
    notifyListeners();
  }

  // ── Device Selection ──
  void setAudioInputDevice(String deviceId) {
    _audioInputDeviceId = deviceId;
    notifyListeners();
  }

  void setAudioOutputDevice(String deviceId) {
    _audioOutputDeviceId = deviceId;
    notifyListeners();
  }

  // ── Quality Settings ──
  void setVideoResolution(VideoResolution resolution) {
    _qualitySettings = _qualitySettings.copyWith(videoResolution: resolution);
    notifyListeners();
  }

  void setAudioBitrate(AudioBitrate bitrate) {
    _qualitySettings = _qualitySettings.copyWith(audioBitrate: bitrate);
    notifyListeners();
  }

  void setVideoBitrate(VideoBitrate bitrate) {
    _qualitySettings = _qualitySettings.copyWith(videoBitrate: bitrate);
    notifyListeners();
  }

  void setFrameRate(FrameRate fps) {
    _qualitySettings = _qualitySettings.copyWith(frameRate: fps);
    notifyListeners();
  }

  void setQualitySettings(MediaQualitySettings settings) {
    _qualitySettings = settings;
    notifyListeners();
  }

  // ── Volume Controls ──
  void setMasterVolume(double volume) {
    _masterVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setInputVolume(double volume) {
    _inputVolume = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void setParticipantVolume(String participantId, double volume) {
    _participantVolumes[participantId] = volume.clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleParticipantMute(String participantId) {
    _participantMuted[participantId] =
        !(_participantMuted[participantId] ?? false);
    notifyListeners();
  }

  double getParticipantVolume(String participantId) {
    return _participantVolumes[participantId] ?? 1.0;
  }

  bool isParticipantMuted(String participantId) {
    return _participantMuted[participantId] ?? false;
  }
}
