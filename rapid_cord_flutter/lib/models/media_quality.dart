/// Frame-rate presets for getUserMedia / getDisplayMedia constraints.
enum FrameRate {
  fps15(15, '15 fps'),
  fps30(30, '30 fps'),
  fps60(60, '60 fps');

  final int value;
  final String label;
  const FrameRate(this.value, this.label);
}

/// Video resolution presets for getUserMedia constraints.
enum VideoResolution {
  p480(854, 480, '480p'),
  p720(1280, 720, '720p'),
  p1080(1920, 1080, '1080p');

  final int width;
  final int height;
  final String label;
  const VideoResolution(this.width, this.height, this.label);
}

/// Audio bitrate presets (bits per second).
enum AudioBitrate {
  kbps64(64000, '64 kbps'),
  kbps128(128000, '128 kbps');

  final int bps;
  final String label;
  const AudioBitrate(this.bps, this.label);
}

/// Video bitrate presets (bits per second).
enum VideoBitrate {
  kbps500(500000, '500 kbps'),
  kbps1500(1500000, '1.5 Mbps'),
  kbps2500(2500000, '2.5 Mbps'),
  kbps4000(4000000, '4 Mbps');

  final int bps;
  final String label;
  const VideoBitrate(this.bps, this.label);
}

/// Audio processing profile — maps to getUserMedia echo/noise/gain constraints.
enum AudioInputProfile {
  /// Echo cancellation + noise suppression + AGC all enabled.
  voiceIsolation('Voice Isolation'),

  /// All processing disabled — flat recording, best for music / instruments.
  studio('Studio'),

  /// Each processing flag is individually toggled by the user.
  custom('Custom');

  final String label;
  const AudioInputProfile(this.label);
}

/// Holds the current media quality selections.
class MediaQualitySettings {
  final VideoResolution videoResolution;
  final AudioBitrate audioBitrate;
  final VideoBitrate videoBitrate;
  final FrameRate frameRate;

  // ── Audio processing ──────────────────────────────────────────────────────
  final AudioInputProfile audioInputProfile;

  /// Per-flag toggles used when [audioInputProfile] is [AudioInputProfile.custom].
  final bool echoCancellation;
  final bool noiseSuppression;
  final bool autoGainControl;

  // ── Push-to-talk ──────────────────────────────────────────────────────────
  /// When true the mic is muted by default and only unmuted while the PTT key
  /// is held. The [pushToTalkKey] string uses [LogicalKeyboardKey.keyLabel]
  /// (e.g. "F10", "`", "Space").
  final bool pushToTalk;
  final String pushToTalkKey;

  const MediaQualitySettings({
    this.videoResolution = VideoResolution.p720,
    this.audioBitrate = AudioBitrate.kbps128,
    this.videoBitrate = VideoBitrate.kbps2500,
    this.frameRate = FrameRate.fps30,
    this.audioInputProfile = AudioInputProfile.voiceIsolation,
    this.echoCancellation = true,
    this.noiseSuppression = true,
    this.autoGainControl = true,
    this.pushToTalk = false,
    this.pushToTalkKey = 'F10',
  });

  /// Generate getUserMedia video constraints from current settings.
  Map<String, dynamic> get videoConstraints => {
    'width': {'ideal': videoResolution.width},
    'height': {'ideal': videoResolution.height},
    'frameRate': {'ideal': frameRate.value},
  };

  /// Constraints for screen capture via getDisplayMedia.
  Map<String, dynamic> get screenConstraints => {
    'video': {
      'frameRate': {'ideal': frameRate.value},
    },
    'audio': true,
  };

  /// Generate getUserMedia audio constraints from the current profile / flags.
  Map<String, dynamic> get audioConstraints {
    Map<String, dynamic> constraints;
    switch (audioInputProfile) {
      case AudioInputProfile.voiceIsolation:
        constraints = {
          'sampleRate': 48000,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googDucking': false,
          'googAudioMirroring': false,
          'googAutoGainControl': true,
          'googAutoGainControl2': true,
        };
        break;
      case AudioInputProfile.studio:
        constraints = {
          'sampleRate': 48000,
          'echoCancellation': false,
          'noiseSuppression': false,
          'autoGainControl': false,
          'googDucking': false,
          'googAudioMirroring': false,
          'googAutoGainControl': false,
          'googAutoGainControl2': false,
        };
        break;
      case AudioInputProfile.custom:
        constraints = {
          'sampleRate': 48000,
          'echoCancellation': echoCancellation,
          'noiseSuppression': noiseSuppression,
          'autoGainControl': autoGainControl,
          'googDucking': false,
          'googAudioMirroring': false,
          'googAutoGainControl': autoGainControl,
          'googAutoGainControl2': autoGainControl,
        };
        break;
    }

    constraints['optional'] = [
      {'googDucking': false},
      {'googAudioMirroring': false},
    ];
    return constraints;
  }

  MediaQualitySettings copyWith({
    VideoResolution? videoResolution,
    AudioBitrate? audioBitrate,
    VideoBitrate? videoBitrate,
    FrameRate? frameRate,
    AudioInputProfile? audioInputProfile,
    bool? echoCancellation,
    bool? noiseSuppression,
    bool? autoGainControl,
    bool? pushToTalk,
    String? pushToTalkKey,
  }) {
    return MediaQualitySettings(
      videoResolution: videoResolution ?? this.videoResolution,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      frameRate: frameRate ?? this.frameRate,
      audioInputProfile: audioInputProfile ?? this.audioInputProfile,
      echoCancellation: echoCancellation ?? this.echoCancellation,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      autoGainControl: autoGainControl ?? this.autoGainControl,
      pushToTalk: pushToTalk ?? this.pushToTalk,
      pushToTalkKey: pushToTalkKey ?? this.pushToTalkKey,
    );
  }
}
