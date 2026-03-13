import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/media_quality.dart';
import '../providers/call_provider.dart';
import '../providers/media_provider.dart';
import '../services/webrtc_service.dart';
import '../theme/app_colors.dart';

/// Open the full Voice & Video settings dialog.
void showSettingsScreen(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.75),
    builder: (ctx) => const _SettingsDialog(),
    useSafeArea: false,
  );
}

// ── Nav sections ──────────────────────────────────────────────────────────────
enum _SettingsNav { voiceVideo, appearance }

// ── Root dialog ───────────────────────────────────────────────────────────────
class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  _SettingsNav _nav = _SettingsNav.voiceVideo;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Navigator.of(context).pop();
        },
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 40,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920, maxHeight: 680),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Sidebar ──
                  _buildSidebar(),
                  // ── Content ──
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          color: AppColors.contentBg,
                          child: _buildContent(),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Tooltip(
                            message: 'Close  (Esc)',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.controlBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  color: AppColors.textMuted,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 218,
      color: AppColors.serverBar,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── USER SETTINGS ──
          _sidebarLabel('USER SETTINGS'),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.person_rounded,
            label: 'My Account',
            selected: false,
            onTap: () {},
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Divider(color: AppColors.divider, height: 1),
          ),
          // ── APP SETTINGS ──
          _sidebarLabel('APP SETTINGS'),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.headset_rounded,
            label: 'Voice & Video',
            selected: _nav == _SettingsNav.voiceVideo,
            onTap: () => setState(() => _nav = _SettingsNav.voiceVideo),
          ),
          _NavItem(
            icon: Icons.palette_rounded,
            label: 'Appearance',
            selected: _nav == _SettingsNav.appearance,
            onTap: () => setState(() => _nav = _SettingsNav.appearance),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'ESC to close',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sidebarLabel(String text) => Padding(
    padding: const EdgeInsets.only(left: 8, bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _buildContent() {
    switch (_nav) {
      case _SettingsNav.voiceVideo:
        return const _VoiceVideoPage();
      case _SettingsNav.appearance:
        return const _StubPage(
          title: 'Appearance',
          body: 'Theme customisation coming soon.',
        );
    }
  }
}

// ── Sidebar nav item ──────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.channelActive : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.textPrimary : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Voice & Video page ────────────────────────────────────────────────────────
class _VoiceVideoPage extends StatefulWidget {
  const _VoiceVideoPage();

  @override
  State<_VoiceVideoPage> createState() => _VoiceVideoPageState();
}

class _VoiceVideoPageState extends State<_VoiceVideoPage> {
  List<MediaDeviceInfo> _inputs = [];
  List<MediaDeviceInfo> _outputs = [];
  String? _inputId;
  String? _outputId;
  double _micLevel = 0.0;
  StreamSubscription<double>? _levelSub;
  bool _listeningForKey = false;
  // Windows Communications Ducking level: 0=mute, 1=80%, 2=50%, 3=do-nothing
  int _duckingLevel = 3;
  late final CallProvider _callProvider;

  @override
  void initState() {
    super.initState();
    _callProvider = context.read<CallProvider>();
    // Pre-populate from saved MediaProvider values so the correct device is
    // shown as selected even before enumerateDevices() returns.
    final mp = context.read<MediaProvider>();
    _inputId = mp.audioInputDeviceId;
    _outputId = mp.audioOutputDeviceId;
    _loadDevices();
    _callProvider.startMicPreview();
    _levelSub = _callProvider.onLocalAudioLevelChanged.listen((level) {
      if (!mounted) return;
      final mp = context.read<MediaProvider>();
      setState(() {
        _micLevel = mp.isMuted
            ? 0.0
            : (level * 5.0 * mp.inputVolume).clamp(0.0, 1.0);
      });
    });
  }

  @override
  void dispose() {
    _levelSub?.cancel();
    if (_listeningForKey) {
      HardwareKeyboard.instance.removeHandler(_captureKey);
    }
    _callProvider.stopMicPreview();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      if (!mounted) return;
      setState(() {
        _inputs = devices.where((d) => d.kind == 'audioinput').toList();
        _outputs = devices.where((d) => d.kind == 'audiooutput').toList();
        // Use saved device if it's still present; fall back to first.
        final inputIds = _inputs.map((d) => d.deviceId).toSet();
        final outputIds = _outputs.map((d) => d.deviceId).toSet();
        if (_inputId == null || !inputIds.contains(_inputId)) {
          _inputId = _inputs.isNotEmpty ? _inputs.first.deviceId : null;
        }
        if (_outputId == null || !outputIds.contains(_outputId)) {
          _outputId = _outputs.isNotEmpty ? _outputs.first.deviceId : null;
        }
      });
    } catch (_) {}
  }

  Future<void> _applyAudioConstraints(MediaQualitySettings settings) async {
    if (_callProvider.isInCall) {
      await _callProvider.updateAudioConstraints(
        settings,
        audioInputDeviceId: _inputId,
      );
    }
  }

  void _startListeningForKey() {
    setState(() => _listeningForKey = true);
    HardwareKeyboard.instance.addHandler(_captureKey);
  }

  bool _captureKey(KeyEvent e) {
    if (!_listeningForKey) return false;
    if (e is! KeyDownEvent) return false;
    // ESC cancels capture without setting the key.
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      HardwareKeyboard.instance.removeHandler(_captureKey);
      if (mounted) setState(() => _listeningForKey = false);
      return true;
    }
    final mods = {
      LogicalKeyboardKey.shift,
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.alt,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.meta,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    };
    if (mods.contains(e.logicalKey)) return false;
    final label = e.logicalKey.keyLabel.isEmpty
        ? e.logicalKey.debugName ?? 'Unknown'
        : e.logicalKey.keyLabel;
    HardwareKeyboard.instance.removeHandler(_captureKey);
    if (!mounted) return true;
    context.read<MediaProvider>().setPushToTalkKey(label);
    setState(() => _listeningForKey = false);
    return true;
  }

  String _deviceLabel(List<MediaDeviceInfo> list, String? id, String fallback) {
    if (list.isEmpty) return fallback;
    final d = list.firstWhere(
      (d) => d.deviceId == id,
      orElse: () => list.first,
    );
    return d.label.isEmpty ? fallback : d.label;
  }

  @override
  Widget build(BuildContext context) {
    final mediaProv = context.watch<MediaProvider>();
    final qs = mediaProv.qualitySettings;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 56, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Page title ──────────────────────────────────────────────────────
          const Text(
            'Voice & Video',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),

          // ── VOICE ──────────────────────────────────────────────────────────
          _sectionHeader('VOICE'),
          const SizedBox(height: 14),

          // Microphone + Speaker dropdowns side-by-side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDeviceDropdown(
                  label: 'Microphone',
                  selectedLabel: _deviceLabel(
                    _inputs,
                    _inputId,
                    'Default Microphone',
                  ),
                  devices: _inputs,
                  onSelected: (id) {
                    setState(() => _inputId = id);
                    mediaProv.setAudioInputDevice(id);
                    _callProvider.updateAudioInputDevice(id);
                  },
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildDeviceDropdown(
                  label: 'Speaker',
                  selectedLabel: _deviceLabel(
                    _outputs,
                    _outputId,
                    'Windows Default',
                  ),
                  devices: _outputs,
                  onSelected: (id) {
                    setState(() => _outputId = id);
                    mediaProv.setAudioOutputDevice(id);
                    _callProvider.setAudioOutputDevice(id);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Volume sliders side-by-side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildVolumeSlider(
                  'Microphone Volume',
                  mediaProv.inputVolume,
                  mediaProv.setInputVolume,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: _buildVolumeSlider(
                  'Speaker Volume',
                  mediaProv.masterVolume,
                  mediaProv.setMasterVolume,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mic Test button + meter
          Row(
            children: [
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.blurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: const Text('Mic Test'),
              ),
              const SizedBox(width: 16),
              Expanded(child: _buildMicMeter()),
            ],
          ),
          const SizedBox(height: 28),

          const Divider(color: AppColors.divider),
          const SizedBox(height: 20),

          // ── INPUT PROFILE ──────────────────────────────────────────────────
          _sectionHeader('INPUT PROFILE'),
          const SizedBox(height: 12),

          _ProfileRadioItem(
            profile: AudioInputProfile.voiceIsolation,
            description:
                'Just your beautiful voice: let Discord cut through the noise',
            selected: qs.audioInputProfile == AudioInputProfile.voiceIsolation,
            onTap: () async {
              final u = mediaProv.setAudioInputProfile(
                AudioInputProfile.voiceIsolation,
              );
              await _callProvider.setMicVoiceProfile(
                AudioInputProfile.voiceIsolation,
              );
              await _applyAudioConstraints(u);
            },
          ),
          _ProfileRadioItem(
            profile: AudioInputProfile.studio,
            description: 'Pure audio: open mic with no processing',
            selected: qs.audioInputProfile == AudioInputProfile.studio,
            onTap: () async {
              final u = mediaProv.setAudioInputProfile(
                AudioInputProfile.studio,
              );
              await _callProvider.setMicVoiceProfile(AudioInputProfile.studio);
              await _applyAudioConstraints(u);
            },
          ),
          _ProfileRadioItem(
            profile: AudioInputProfile.custom,
            description: 'Advanced mode: give me all the buttons and dials!',
            selected: qs.audioInputProfile == AudioInputProfile.custom,
            onTap: () async {
              final u = mediaProv.setAudioInputProfile(
                AudioInputProfile.custom,
              );
              await _callProvider.setMicVoiceProfile(AudioInputProfile.custom);
              await _applyAudioConstraints(u);
            },
          ),

          // Custom toggles
          if (qs.audioInputProfile == AudioInputProfile.custom) ...[
            const SizedBox(height: 8),
            _SettingsToggleRow(
              title: 'Echo Cancellation',
              description: 'Reduces echo from your speakers.',
              value: qs.echoCancellation,
              onChanged: (v) {
                final u = mediaProv.setEchoCancellation(v);
                _applyAudioConstraints(u).ignore();
              },
            ),
            _SettingsToggleRow(
              title: 'Noise Suppression',
              description: 'Filters steady background noise.',
              value: qs.noiseSuppression,
              onChanged: (v) {
                final u = mediaProv.setNoiseSuppression(v);
                _applyAudioConstraints(u).ignore();
              },
            ),
            _SettingsToggleRow(
              title: 'Auto Gain Control',
              description: 'Automatically adjusts mic sensitivity.',
              value: qs.autoGainControl,
              onChanged: (v) {
                final u = mediaProv.setAutoGainControl(v);
                _applyAudioConstraints(u).ignore();
              },
            ),
          ],

          const SizedBox(height: 28),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 20),

          // ── PUSH-TO-TALK ───────────────────────────────────────────────────
          _sectionHeader('PUSH-TO-TALK'),
          const SizedBox(height: 12),

          _SettingsToggleRow(
            title: 'Push-to-Talk',
            description: 'Hold a key to unmute your mic.',
            value: qs.pushToTalk,
            onChanged: (v) => mediaProv.setPushToTalk(v),
          ),

          if (qs.pushToTalk) ...[
            const SizedBox(height: 10),
            _buildPttKeybindRow(qs),
          ],

          const SizedBox(height: 28),
          const Divider(color: AppColors.divider),
          const SizedBox(height: 20),

          // ── SYSTEM (Windows-only) ──────────────────────────────────────────
          if (WebRTC.platformIsWindows) ..._buildWindowsSystemSection(),

          // ── STREAMING ─────────────────────────────────────────────────────
          _sectionHeader('STREAMING'),
          const SizedBox(height: 16),
          _buildSystemAudioGateRow(mediaProv),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Section helpers ─────────────────────────────────────────────────────────

  Widget _sectionHeader(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );

  Widget _buildDeviceDropdown({
    required String label,
    required String selectedLabel,
    required List<MediaDeviceInfo> devices,
    required void Function(String) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        PopupMenuButton<String>(
          color: AppColors.sidebarBg,
          offset: const Offset(0, 46),
          onSelected: onSelected,
          itemBuilder: (ctx) => devices
              .map(
                (d) => PopupMenuItem<String>(
                  value: d.deviceId,
                  child: Text(
                    d.label.isEmpty ? 'Unknown Device' : d.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
              .toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.controlBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedLabel,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeSlider(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: AppColors.blurple,
            inactiveTrackColor: AppColors.controlBg,
            thumbColor: Colors.white,
            overlayColor: AppColors.blurple.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(value: value, min: 0, max: 1.0, onChanged: onChanged),
        ),
      ],
    );
  }

  Widget _buildMicMeter() {
    const numBars = 32;
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(numBars, (i) {
          final threshold = i / numBars;
          final active = _micLevel > threshold;
          final color = threshold < 0.5
              ? Colors.green
              : threshold < 0.8
              ? Colors.yellow
              : Colors.red;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 40),
            width: 5,
            height: active ? 28.0 : 14.0,
            decoration: BoxDecoration(
              color: active ? color : AppColors.controlBg,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPttKeybindRow(MediaQualitySettings qs) {
    return Row(
      children: [
        const Text(
          'Keybind:',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: _listeningForKey
                ? AppColors.blurple.withValues(alpha: 0.25)
                : AppColors.controlBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _listeningForKey ? AppColors.blurple : AppColors.divider,
            ),
          ),
          child: Text(
            _listeningForKey ? 'Press a key…' : qs.pushToTalkKey,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: _listeningForKey
                  ? AppColors.blurple
                  : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (!_listeningForKey)
          TextButton(
            onPressed: _startListeningForKey,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.blurple,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Edit',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildWindowsSystemSection() {
    const options = <(int, String, String)>[
      (3, 'Do nothing', 'No volume changes when mic opens (recommended)'),
      (2, 'Reduce by 50%', 'Lower other sounds to 50% when mic is active'),
      (1, 'Reduce by 80%', 'Lower other sounds to 20% when mic is active'),
      (0, 'Mute all', 'Silence all other audio while mic is open'),
    ];
    final selected = options.firstWhere(
      (o) => o.$1 == _duckingLevel,
      orElse: () => options.first,
    );
    return [
      _sectionHeader('SYSTEM'),
      const SizedBox(height: 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'COMMUNICATIONS DUCKING',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Controls whether Windows lowers other app volumes when your mic is active.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          PopupMenuButton<int>(
            color: AppColors.sidebarBg,
            offset: const Offset(0, 46),
            onSelected: (level) {
              setState(() => _duckingLevel = level);
              WebRTCService.setWindowsDuckingLevel(level);
            },
            itemBuilder: (ctx) => options
                .map(
                  (o) => PopupMenuItem<int>(
                    value: o.$1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.$2,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          o.$3,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.controlBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    selected.$2,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 28),
      const Divider(color: AppColors.divider),
      const SizedBox(height: 20),
    ];
  }

  Widget _buildSystemAudioGateRow(MediaProvider mediaProv) {
    final t = mediaProv.systemAudioGateThreshold;
    final pct = (t / 0.15 * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stream Attenuation',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Automatically silence system audio below this level.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              t <= 0 ? 'Off' : '$pct%',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            activeTrackColor: AppColors.blurple,
            inactiveTrackColor: AppColors.controlBg,
            thumbColor: Colors.white,
            overlayColor: AppColors.blurple.withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: t,
            min: 0,
            max: 0.15,
            divisions: 15,
            onChanged: (v) => mediaProv.setSystemAudioGateThreshold(v),
          ),
        ),
      ],
    );
  }
}

// ── Profile radio row ─────────────────────────────────────────────────────────
class _ProfileRadioItem extends StatelessWidget {
  final AudioInputProfile profile;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileRadioItem({
    required this.profile,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.blurple : AppColors.textMuted,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.blurple,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings toggle row (title + description + switch) ────────────────────────
class _SettingsToggleRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.blurple,
            inactiveThumbColor: AppColors.textMuted,
            inactiveTrackColor: AppColors.controlBg,
          ),
        ],
      ),
    );
  }
}

// ── Stub page ─────────────────────────────────────────────────────────────────
class _StubPage extends StatelessWidget {
  final String title;
  final String body;

  const _StubPage({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
