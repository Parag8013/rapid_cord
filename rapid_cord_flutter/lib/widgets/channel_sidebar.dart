import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../providers/call_provider.dart';
import '../providers/channel_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_colors.dart';
import 'user_panel.dart';

/// Sidebar showing text and voice channels, grouped by category.
class ChannelSidebar extends StatelessWidget {
  const ChannelSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ChannelProvider, CallProvider>(
      builder: (context, channelProv, callProv, _) {
        return Container(
          width: 240,
          decoration: const BoxDecoration(
            color: AppColors.sidebarBg,
            border: Border(
              right: BorderSide(color: AppColors.divider, width: 1),
            ),
          ),
          child: Column(
            children: [
              // ── Server Header ──
              _buildServerHeader(),

              const Divider(color: AppColors.divider, height: 1),

              // ── Channel List ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(top: 12),
                  children: [
                    _buildCategoryHeader('Text channels', context),
                    ...channelProv.textChannels.map(
                      (ch) => _buildChannelTile(context, ch, channelProv),
                    ),
                    const SizedBox(height: 12),
                    _buildCategoryHeader('Voice channels', context),
                    ...channelProv.voiceChannels.map(
                      (ch) => _buildVoiceChannelTile(
                        context,
                        ch,
                        channelProv,
                        callProv,
                      ),
                    ),
                  ],
                ),
              ),

              // ── User Panel ──
              const UserPanel(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildServerHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: AppColors.sidebarBg,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'RapidCord Server',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String label, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 12,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.add, size: 16, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelTile(
    BuildContext context,
    Channel channel,
    ChannelProvider prov,
  ) {
    final isSelected = prov.selectedChannel?.id == channel.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => prov.selectChannel(channel),
          hoverColor: AppColors.channelHover,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.channelActive : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(
                  channel.icon,
                  size: 20,
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    channel.name,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceChannelTile(
    BuildContext context,
    Channel channel,
    ChannelProvider prov,
    CallProvider callProv,
  ) {
    final isSelected = prov.selectedChannel?.id == channel.id;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => prov.selectChannel(channel),
          hoverColor: AppColors.channelHover,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.channelActive : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: 20,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        channel.name,
                        style: TextStyle(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
                // Show live participants from presence polling.
                // When the local user is in this channel we use CallProvider
                // for richer data (speaking states etc.); otherwise we rely
                // on the REST-polled connectedUserIds which are visible even
                // before the local user joins.
                Builder(
                  builder: (context) {
                    final inThisChannel =
                        callProv.isInCall &&
                        callProv.currentChannelId == channel.id;
                    final members = inThisChannel
                        ? callProv.roomMembers
                        : channel.connectedUserIds;
                    if (members.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(left: 28, top: 4),
                      child: Column(
                        children: members.map((entry) {
                          // When in-call, entry is a user ID — resolve name.
                          // When relying on presence poll, entry is already
                          // a display name returned by the server.
                          String displayName;
                          if (inThisChannel) {
                            displayName = entry == callProv.userId
                                ? context
                                          .read<UserProvider>()
                                          .username
                                          .isNotEmpty
                                      ? context.read<UserProvider>().username
                                      : entry
                                : callProv.peerName(entry);
                          } else {
                            displayName = entry;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: AppColors.purple.withValues(
                                      alpha: 0.3,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
