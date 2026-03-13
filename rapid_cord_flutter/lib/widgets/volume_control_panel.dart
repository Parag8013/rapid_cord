import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';
import '../theme/app_colors.dart';

/// Shows the volume control popup.
void showVolumeControlPanel(BuildContext context, RelativeRect position) {
  showMenu(
    context: context,
    position: position,
    color: Colors.transparent,
    elevation: 0,
    items: [
      PopupMenuItem(
        enabled: false,
        padding: EdgeInsets.zero,
        child: const _VolumeControlContent(),
      ),
    ],
  );
}

class _VolumeControlContent extends StatelessWidget {
  const _VolumeControlContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sidebarBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Consumer<MediaProvider>(
        builder: (context, mediaProv, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              const Row(
                children: [
                  Icon(
                    Icons.volume_up_rounded,
                    size: 18,
                    color: AppColors.purpleLight,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'VOLUME',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Master Volume ──
              _VolumeSlider(
                label: 'Master Volume',
                icon: Icons.speaker_rounded,
                value: mediaProv.masterVolume,
                onChanged: mediaProv.setMasterVolume,
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.divider, height: 1),
              const SizedBox(height: 12),

              // ── Per-Participant ──
              const Text(
                'PARTICIPANTS',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),

              // Mock participants
              _ParticipantVolume(
                name: 'Chini',
                participantId: 'user-1',
                volume: mediaProv.getParticipantVolume('user-1'),
                isMuted: mediaProv.isParticipantMuted('user-1'),
                onVolumeChanged: (v) =>
                    mediaProv.setParticipantVolume('user-1', v),
                onToggleMute: () => mediaProv.toggleParticipantMute('user-1'),
              ),
              const SizedBox(height: 4),
              _ParticipantVolume(
                name: 'Pok',
                participantId: 'user-2',
                volume: mediaProv.getParticipantVolume('user-2'),
                isMuted: mediaProv.isParticipantMuted('user-2'),
                onVolumeChanged: (v) =>
                    mediaProv.setParticipantVolume('user-2', v),
                onToggleMute: () => mediaProv.toggleParticipantMute('user-2'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VolumeSlider extends StatelessWidget {
  final String label;
  final IconData icon;
  final double value;
  final ValueChanged<double> onChanged;

  const _VolumeSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${(value * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: AppColors.purple,
                  inactiveTrackColor: AppColors.textMuted.withValues(
                    alpha: 0.3,
                  ),
                  thumbColor: AppColors.textPrimary,
                  overlayColor: AppColors.purple.withValues(alpha: 0.2),
                ),
                child: Slider(value: value, onChanged: onChanged),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParticipantVolume extends StatelessWidget {
  final String name;
  final String participantId;
  final double volume;
  final bool isMuted;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  const _ParticipantVolume({
    required this.name,
    required this.participantId,
    required this.volume,
    required this.isMuted,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.channelActive.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purple,
            ),
            child: Center(
              child: Text(
                name[0],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Name
          SizedBox(
            width: 40,
            child: Text(
              name,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Slider
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: isMuted
                    ? AppColors.textMuted
                    : AppColors.purple,
                inactiveTrackColor: AppColors.textMuted.withValues(alpha: 0.2),
                thumbColor: AppColors.textPrimary,
                overlayColor: AppColors.purple.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: isMuted ? 0 : volume,
                onChanged: isMuted ? null : onVolumeChanged,
              ),
            ),
          ),
          // Mute button
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: onToggleMute,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 16,
                color: isMuted ? AppColors.dnd : AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
