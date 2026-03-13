import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/media_provider.dart';
import '../providers/user_provider.dart';
import '../services/pop_out_service.dart';
import '../theme/app_colors.dart';
import 'quality_settings_panel.dart';
import 'screen_source_picker.dart';
import 'soundboard_panel.dart';
import 'volume_control_panel.dart';
import 'audio_settings_panel.dart';

/// Bottom media controls bar for voice/video channels.
///
/// Matches the Discord-style layout: mic, camera (with dropdown arrow),
/// screen share, grid view, noise suppression, more, and hang up.
class MediaControls extends StatelessWidget {
  final VoidCallback? onHangUp;

  /// Channel info passed directly so pop-out works even before WebRTC joins.
  final String? channelId;
  final String? channelName;

  const MediaControls({
    super.key,
    this.onHangUp,
    this.channelId,
    this.channelName,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, mediaProv, _) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.serverBar.withValues(alpha: 0.9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Invite Button ──
              _ActionChip(label: 'Invite', onTap: () {}),

              const Spacer(),

              // ── Mic Toggle (with dropdown arrow) ──
              Builder(
                builder: (context) {
                  return _ControlButton(
                    icon: mediaProv.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    isActive: !mediaProv.isMuted,
                    onTap: mediaProv.toggleMute,
                    onDropdownTap: () {
                      final box = context.findRenderObject() as RenderBox;
                      final offset = box.localToGlobal(Offset.zero);
                      showAudioSettingsPanel(context, offset);
                    },
                    tooltip: mediaProv.isMuted ? 'Unmute' : 'Mute',
                    hasDropdown: true,
                  );
                },
              ),
              const SizedBox(width: 8),

              // ── Camera Toggle (with dropdown arrow) ──
              _ControlButton(
                icon: mediaProv.isCameraOn
                    ? Icons.videocam_rounded
                    : Icons.videocam_off_rounded,
                isActive: mediaProv.isCameraOn,
                onTap: mediaProv.toggleCamera,
                tooltip: mediaProv.isCameraOn
                    ? 'Turn Off Camera'
                    : 'Turn On Camera',
                hasDropdown: true,
              ),
              const SizedBox(width: 8),

              // ── Screen Share ──
              _ControlButton(
                icon: Icons.screen_share_rounded,
                isActive: mediaProv.isScreenSharing,
                onTap: () {
                  if (mediaProv.isScreenSharing) {
                    context.read<CallProvider>().stopScreenShare();
                    mediaProv.toggleScreenShare();
                  } else {
                    final callProv = context.read<CallProvider>();
                    showPreStreamDialog(
                      context,
                      onStart: (settings) {
                        showScreenSourcePicker(context).then((result) {
                          if (result == null) return; // user cancelled
                          mediaProv.toggleScreenShare();
                          callProv.startScreenShare(
                            settings,
                            result.source,
                            shareAudio: result.shareAudio,
                          );
                        });
                      },
                    );
                  }
                },
                tooltip: mediaProv.isScreenSharing
                    ? 'Stop Sharing'
                    : 'Share Screen',
              ),
              const SizedBox(width: 8),

              // ── Grid View ──
              _ControlButton(
                icon: Icons.grid_view_rounded,
                isActive: false,
                onTap: () {},
                tooltip: 'Grid View',
              ),
              const SizedBox(width: 8),

              // ── Soundboard ──
              _ControlButton(
                icon: Icons.dashboard_rounded,
                isActive: false,
                onTap: () => showSoundboardPanel(context),
                tooltip: 'Soundboard',
              ),
              const SizedBox(width: 8),

              // ── Noise Suppression ──
              _ControlButton(
                icon: Icons.graphic_eq_rounded,
                isActive: mediaProv.isNoiseSuppression,
                onTap: mediaProv.toggleNoiseSuppression,
                tooltip: 'Noise Suppression',
              ),
              const SizedBox(width: 8),

              // ── More Options ──
              _ControlButton(
                icon: Icons.more_horiz_rounded,
                isActive: false,
                onTap: () => showQualitySettingsPanel(context),
                tooltip: 'Stream Quality',
              ),
              const SizedBox(width: 16),

              // ── Hang Up ──
              _HangUpButton(onTap: onHangUp ?? () {}),

              const Spacer(),

              // ── Right-side controls ──
              Builder(
                builder: (context) {
                  return _ControlButton(
                    icon: Icons.volume_up_rounded,
                    isActive: true,
                    onTap: () {
                      final box = context.findRenderObject() as RenderBox;
                      final offset = box.localToGlobal(Offset.zero);
                      showVolumeControlPanel(
                        context,
                        RelativeRect.fromLTRB(
                          offset.dx,
                          offset.dy - 300,
                          offset.dx + box.size.width,
                          offset.dy,
                        ),
                      );
                    },
                    tooltip: 'Volume',
                    compact: true,
                  );
                },
              ),
              const SizedBox(width: 4),
              if (!PopOutService.isSecondaryWindow)
                _ControlButton(
                  icon: Icons.picture_in_picture_alt_rounded,
                  isActive: false,
                  onTap: () async {
                    final callProv = context.read<CallProvider>();
                    final mediaProv = context.read<MediaProvider>();
                    final userProv = context.read<UserProvider>();
                    final chatProv = context.read<ChatProvider>();
                    final chId =
                        channelId ?? callProv.currentChannelId ?? 'voice';
                    final chName = channelName ?? 'Voice';
                    final userId = userProv.userId; // numeric sub
                    final username = userProv.username; // display name
                    final jwtToken = userProv.jwtToken;
                    final serverUrl = callProv.serverUrl ?? '';
                    // Snapshot chat history before any async gap.
                    final history = chatProv.getMessages('$chId-voice');

                    // Send handoff_start to the server so our roster slot is
                    // preserved while the new window connects.
                    await callProv.sendHandoffStart();
                    mediaProv.leaveVoiceChannel();

                    // Spawn the pop-out window with isHandoff: true so it
                    // connects with ?handoff=true and completes the handoff.
                    await PopOutService.instance.openPopOut(
                      channelId: chId,
                      channelName: chName,
                      userId: userId,
                      username: username,
                      jwtToken: jwtToken,
                      serverUrl: serverUrl,
                      isHandoff: true,
                      chatHistory: history,
                    );
                  },
                  tooltip: 'Pop Out',
                  compact: true,
                ),
              const SizedBox(width: 4),
              _ControlButton(
                icon: Icons.fullscreen_rounded,
                isActive: false,
                onTap: () {},
                tooltip: 'Fullscreen',
                compact: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Internal Widgets ──

class _ActionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onDropdownTap;
  final String tooltip;
  final bool hasDropdown;
  final bool compact;

  const _ControlButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.onDropdownTap,
    required this.tooltip,
    this.hasDropdown = false,
    this.compact = false,
  });

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.controlBg.withValues(alpha: 0.8)
                : AppColors.controlBg.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(widget.compact ? 6 : 24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.compact ? 6 : 10,
                    widget.compact ? 6 : 10,
                    widget.hasDropdown ? 2 : (widget.compact ? 6 : 10),
                    widget.compact ? 6 : 10,
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.compact ? 18 : 22,
                    color: widget.isActive
                        ? AppColors.textPrimary
                        : AppColors.controlInactive,
                  ),
                ),
              ),
              if (widget.hasDropdown)
                GestureDetector(
                  onTap: widget.onDropdownTap ?? widget.onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      2,
                      widget.compact ? 6 : 10,
                      widget.compact ? 6 : 10,
                      widget.compact ? 6 : 10,
                    ),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HangUpButton extends StatefulWidget {
  final VoidCallback onTap;

  const _HangUpButton({required this.onTap});

  @override
  State<_HangUpButton> createState() => _HangUpButtonState();
}

class _HangUpButtonState extends State<_HangUpButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Disconnect',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _hovered
                  ? AppColors.hangUp.withValues(alpha: 0.9)
                  : AppColors.hangUp,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.call_end_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
