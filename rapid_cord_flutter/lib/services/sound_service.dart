import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sound effect types used throughout the app.
enum SoundEffect {
  channelJoin('sounds/channel_join.wav'),
  channelLeave('sounds/channel_leave.wav'),
  screenShareOn('sounds/screen_share_on.wav'),
  screenShareOff('sounds/screen_share_off.wav'),
  notification('sounds/notification.wav'),
  soundboardAirhorn('sounds/soundboard_airhorn.wav'),
  soundboardRimshot('sounds/soundboard_rimshot.wav'),
  soundboardSadTrombone('sounds/soundboard_sad_trombone.wav'),
  soundboardApplause('sounds/soundboard_applause.wav'),
  soundboardCrickets('sounds/soundboard_crickets.wav'),
  soundboardDrumRoll('sounds/soundboard_drum_roll.wav');

  final String assetPath;
  const SoundEffect(this.assetPath);
}

/// Singleton service for playing sound effects.
///
/// Uses `audioplayers` to play asset-bundled WAV files.
/// Gracefully disables itself when the audio plugin is unavailable
/// (e.g. in secondary windows spawned by desktop_multi_window).
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  AudioPlayer? _effectPlayer;
  bool enabled = true;
  bool _pluginAvailable = true;

  AudioPlayer get _player => _effectPlayer ??= AudioPlayer();

  /// Play a sound effect.
  Future<void> play(SoundEffect effect) async {
    if (!enabled || !_pluginAvailable) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(effect.assetPath));
    } on MissingPluginException {
      _pluginAvailable = false;
      debugPrint('[SoundService] Audio plugin unavailable — disabling sounds');
    } catch (e) {
      debugPrint('[SoundService] Failed to play ${effect.name}: $e');
    }
  }

  /// Play a soundboard effect (uses a separate player to avoid cutting off).
  Future<void> playSoundboard(SoundEffect effect) async {
    if (!_pluginAvailable) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource(effect.assetPath));
      player.onPlayerComplete.listen((_) => player.dispose());
    } on MissingPluginException {
      _pluginAvailable = false;
      debugPrint('[SoundService] Audio plugin unavailable — disabling sounds');
    } catch (e) {
      debugPrint('[SoundService] Failed to play soundboard ${effect.name}: $e');
    }
  }

  void dispose() {
    _effectPlayer?.dispose();
    _effectPlayer = null;
  }
}
