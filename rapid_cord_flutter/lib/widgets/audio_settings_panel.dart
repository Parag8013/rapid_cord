import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/media_quality.dart';
import '../providers/call_provider.dart';
import '../providers/media_provider.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';

void showAudioSettingsPanel(BuildContext context, Offset offset) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    pageBuilder: (context, a1, a2) {
      return Stack(
        children: [
          Positioned(
            left: offset.dx,
            bottom: MediaQuery.of(context).size.height - offset.dy + 10,
            child: Material(
              color: Colors.transparent,
              child: const AudioSettingsPanel(),
            ),
          ),
        ],
      );
    },
  );
}

class AudioSettingsPanel extends StatefulWidget {
  const AudioSettingsPanel({super.key});

  @override
  State<AudioSettingsPanel> createState() => _AudioSettingsPanelState();
}

class _AudioSettingsPanelState extends State<AudioSettingsPanel> {
  List<MediaDeviceInfo> _audioInputs = [];
  List<MediaDeviceInfo> _audioOutputs = [];
  String? _selectedInputId;
  String? _selectedOutputId;
  StreamSubscription<double>? _audioLevelSub;
  double _micLevel = 0.0;
  late final CallProvider _callProvider;

  @override
  void initState() {
    super.initState();
    _callProvider = context.read<CallProvider>();
    // Pre-populate from saved device IDs so the selected device is shown
    // correctly before enumerateDevices() completes.
    final mp = context.read<MediaProvider>();
    _selectedInputId = mp.audioInputDeviceId;
    _selectedOutputId = mp.audioOutputDeviceId;
    _loadDevices();
    _callProvider.startMicPreview();
    _audioLevelSub = _callProvider.onLocalAudioLevelChanged.listen((level) {
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
    _audioLevelSub?.cancel();
    _callProvider.stopMicPreview();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      if (!mounted) return;
      setState(() {
        _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
        _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
        // Keep saved device if it still exists; fall back to first.
        final inIds = _audioInputs.map((d) => d.deviceId).toSet();
        final outIds = _audioOutputs.map((d) => d.deviceId).toSet();
        if (_selectedInputId == null || !inIds.contains(_selectedInputId)) {
          _selectedInputId = _audioInputs.isNotEmpty
              ? _audioInputs.first.deviceId
              : null;
        }
        if (_selectedOutputId == null || !outIds.contains(_selectedOutputId)) {
          _selectedOutputId = _audioOutputs.isNotEmpty
              ? _audioOutputs.first.deviceId
              : null;
        }
      });
    } catch (_) {}
  }

  String _label(List<MediaDeviceInfo> list, String? id, String fallback) {
    if (list.isEmpty) return fallback;
    final d = list.firstWhere(
      (d) => d.deviceId == id,
      orElse: () => list.first,
    );
    return d.label.isEmpty ? fallback : d.label;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 268,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.serverBar,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mic row
          _DeviceRow(
            icon: Icons.mic_rounded,
            label: _label(_audioInputs, _selectedInputId, 'Microphone'),
            devices: _audioInputs,
            onSelected: (id) {
              setState(() => _selectedInputId = id);
              context.read<MediaProvider>().setAudioInputDevice(id);
              _callProvider.updateAudioInputDevice(id);
            },
          ),

          // Input Profile row
          _ProfileRow(callProvider: _callProvider),

          // Speaker row
          _DeviceRow(
            icon: Icons.volume_up_rounded,
            label: _label(_audioOutputs, _selectedOutputId, 'Speaker'),
            devices: _audioOutputs,
            onSelected: (id) {
              setState(() => _selectedOutputId = id);
              context.read<MediaProvider>().setAudioOutputDevice(id);
              _callProvider.setAudioOutputDevice(id);
            },
          ),

          // Mic level meter
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: _buildMeter(),
          ),

          const Divider(
            color: AppColors.divider,
            height: 1,
            indent: 12,
            endIndent: 12,
          ),

          // Open full settings
          InkWell(
            onTap: () {
              Navigator.of(context).pop(); // close popup first
              showSettingsScreen(context);
            },
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(10),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.settings_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Voice & Video Settings',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeter() {
    const numBars = 28;
    return Row(
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
          height: active ? 16.0 : 8.0,
          decoration: BoxDecoration(
            color: active ? color : AppColors.controlBg,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ── Compact device row ────────────────────────────────────────────────────────
class _DeviceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<MediaDeviceInfo> devices;
  final void Function(String) onSelected;

  const _DeviceRow({
    required this.icon,
    required this.label,
    required this.devices,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: AppColors.controlBg,
      offset: const Offset(0, 36),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Input Profile row ─────────────────────────────────────────────────────────
class _ProfileRow extends StatelessWidget {
  final CallProvider callProvider;

  const _ProfileRow({required this.callProvider});

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MediaProvider>();
    final current = mp.qualitySettings.audioInputProfile;

    return PopupMenuButton<AudioInputProfile>(
      color: AppColors.controlBg,
      // Open the submenu to the right of the panel
      offset: const Offset(270, 0),
      onSelected: (profile) async {
        final updated = mp.setAudioInputProfile(profile);
        // Apply native C++ processing first (no-op when not built with RNNoise).
        await callProvider.setMicVoiceProfile(profile);
        // Then re-acquire the mic with the new EC/NS/AGC constraints.
        if (callProvider.isInCall) {
          await callProvider.updateAudioConstraints(
            updated,
            audioInputDeviceId: mp.audioInputDeviceId,
          );
        }
      },
      itemBuilder: (ctx) => AudioInputProfile.values
          .map(
            (p) => PopupMenuItem<AudioInputProfile>(
              value: p,
              child: Row(
                children: [
                  Icon(
                    current == p
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: current == p
                        ? AppColors.blurple
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    p.label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(
              Icons.tune_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                current.label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
