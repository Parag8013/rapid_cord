import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/media_provider.dart';
import '../providers/user_provider.dart';
import '../screens/settings_screen.dart';
import '../theme/app_colors.dart';

/// Bottom panel in the sidebar showing current user info and mute/deafen toggles.
class UserPanel extends StatelessWidget {
  const UserPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MediaProvider, UserProvider>(
      builder: (context, mediaProv, userProv, _) {
        final username = userProv.username.isEmpty ? 'User' : userProv.username;
        final avatarLetter = username[0].toUpperCase();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: const BoxDecoration(
            color: AppColors.serverBar,
            border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [AppColors.purple, AppColors.blurple],
                  ),
                ),
                child: Center(
                  child: Text(
                    avatarLetter,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Name & status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      mediaProv.isInVoiceChannel ? 'In Voice' : 'Online',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Mute toggle
              _ControlIconButton(
                icon: mediaProv.isMuted
                    ? Icons.mic_off_rounded
                    : Icons.mic_rounded,
                isActive: !mediaProv.isMuted,
                onTap: mediaProv.toggleMute,
                tooltip: mediaProv.isMuted ? 'Unmute' : 'Mute',
              ),

              // Deafen toggle
              _ControlIconButton(
                icon: mediaProv.isDeafened
                    ? Icons.headset_off_rounded
                    : Icons.headset_rounded,
                isActive: !mediaProv.isDeafened,
                onTap: mediaProv.toggleDeafen,
                tooltip: mediaProv.isDeafened ? 'Undeafen' : 'Deafen',
              ),

              // Settings
              _ControlIconButton(
                icon: Icons.settings_rounded,
                isActive: true,
                onTap: () => showSettingsScreen(context),
                tooltip: 'Settings',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlIconButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final String tooltip;

  const _ControlIconButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            size: 18,
            color: isActive ? AppColors.textSecondary : AppColors.dnd,
          ),
        ),
      ),
    );
  }
}
