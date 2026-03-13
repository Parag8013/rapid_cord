import 'dart:async';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../providers/call_provider.dart';
import '../providers/channel_provider.dart';
import '../providers/media_provider.dart';
import '../providers/user_provider.dart';
import '../services/pop_out_service.dart';
import '../theme/app_colors.dart';
import '../widgets/channel_sidebar.dart';
import 'text_channel_screen.dart';
import 'voice_channel_screen.dart';

/// Thin wrapper around [MainLayout] that listens for reverse-handoff events
/// from the pop-out window and rejoins the call in the main engine.
class MainLayoutWithHandoff extends StatefulWidget {
  const MainLayoutWithHandoff({super.key});

  @override
  State<MainLayoutWithHandoff> createState() => _MainLayoutWithHandoffState();
}

class _MainLayoutWithHandoffState extends State<MainLayoutWithHandoff> {
  late final StreamSubscription<Map<String, String>> _handoffSub;

  @override
  void initState() {
    super.initState();
    _handoffSub = PopOutService.instance.onHandoffBack.listen(_onHandoffBack);
  }

  Future<void> _onHandoffBack(Map<String, String> args) async {
    if (!mounted) return;
    final channelId = args['channelId'] ?? '';
    if (channelId.isEmpty) return;

    final callProv = context.read<CallProvider>();
    final mediaProv = context.read<MediaProvider>();

    mediaProv.joinVoiceChannel();
    await callProv.handoffJoin(channelId);
    debugPrint('[MainLayout] Reverse handoff complete for channel $channelId');
  }

  @override
  void dispose() {
    _handoffSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const MainLayout();
}

/// The top-level desktop layout: server bar | channel sidebar | main content.
///
/// Features animated transitions when switching between channels.
class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Row(
          children: [
            // ── Server Icon Bar ──
            _buildServerBar(context),

            // ── Channel Sidebar ──
            SizedBox(
              width: 240,
              child: Column(
                children: [
                  const Expanded(child: ChannelSidebar()),
                  Consumer2<CallProvider, ChannelProvider>(
                    builder: (context, callProv, channelProv, _) {
                      if (!callProv.isInCall) return const SizedBox.shrink();
                      if (channelProv.selectedChannel?.type ==
                          ChannelType.voice) {
                        return const SizedBox.shrink();
                      }
                      return _VoiceConnectedBar(
                        channelId: callProv.currentChannelId ?? '',
                        onDisconnect: () {
                          callProv.leaveCall();
                          context.read<MediaProvider>().leaveVoiceChannel();
                        },
                        onReturn: () {
                          final matches = channelProv.voiceChannels
                              .where((c) => c.id == callProv.currentChannelId)
                              .toList();
                          if (matches.isNotEmpty) {
                            channelProv.selectChannel(matches.first);
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── Main Content Area ──
            Expanded(
              child: Container(
                decoration: const BoxDecoration(color: AppColors.contentBg),
                child: Consumer2<ChannelProvider, PopOutService>(
                  builder: (context, channelProv, popOutSvc, _) {
                    final selected = channelProv.selectedChannel;
                    if (selected == null) {
                      return const Center(
                        child: Text(
                          'Select a channel',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      );
                    }

                    // When the voice channel is popped out, show a banner
                    // so the user can still navigate text channels.
                    if (selected.type == ChannelType.voice &&
                        popOutSvc.isPopped) {
                      return _VoicePopOutBanner(
                        key: ValueKey('popout-${selected.id}'),
                        channelId: selected.id,
                        channelName: selected.name,
                      );
                    }

                    // Animated crossfade between screens.
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0.03, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          ),
                        );
                      },
                      child: selected.type == ChannelType.voice
                          ? VoiceChannelScreen(
                              key: ValueKey('voice-${selected.id}'),
                              channelId: selected.id,
                              channelName: selected.name,
                            )
                          : TextChannelScreen(
                              key: ValueKey('text-${selected.id}'),
                              channelId: selected.id,
                              channelName: selected.name,
                            ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerBar(BuildContext context) {
    return Container(
      width: 72,
      color: AppColors.serverBar,
      child: Column(
        children: [
          const SizedBox(height: 12),

          // ── App Logo / Home ──
          _ServerIcon(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.purple, AppColors.blurple],
                ),
              ),
              child: const Center(
                child: Text(
                  'RC',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),

          // Divider
          Container(
            width: 32,
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(1),
            ),
          ),

          // ── Server Icons ──
          _ServerIcon(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: AppColors.channelActive,
              ),
              child: const Center(
                child: Text(
                  'IJV',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),

          // ── Logout ──
          _ServerIcon(
            child: Tooltip(
              message: 'Log out',
              child: GestureDetector(
                onTap: () async {
                  final callProv = context.read<CallProvider>();
                  final userProv = context.read<UserProvider>();
                  final mediaProv = context.read<MediaProvider>();
                  if (callProv.isInCall) {
                    await callProv.leaveCall();
                    mediaProv.leaveVoiceChannel();
                  }
                  await userProv.logout();
                },
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: AppColors.channelActive,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.logout,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Voice pop-out banner — shown in the content area when the voice channel is
// open in a separate window.
// ─────────────────────────────────────────────────────────────────────────────

class _VoicePopOutBanner extends StatelessWidget {
  final String channelId;
  final String channelName;

  const _VoicePopOutBanner({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.contentBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.picture_in_picture_alt_rounded,
                size: 52,
                color: AppColors.purple,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '# $channelName is open in a separate window',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Use the channel list on the left to browse text channels.\nClose the pop-out window to return voice here.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Focus the pop-out window
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Focus Window'),
                  onPressed: () {
                    final svc = context.read<PopOutService>();
                    if (svc.windowId != null) {
                      try {
                        WindowController.fromWindowId(svc.windowId!).show();
                      } catch (_) {}
                    }
                  },
                ),
                const SizedBox(width: 12),
                // Close pop-out gracefully
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textMuted,
                    side: const BorderSide(color: AppColors.divider),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Close Pop-out'),
                  onPressed: () => context.read<PopOutService>().requestClose(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerIcon extends StatefulWidget {
  final Widget child;

  const _ServerIcon({required this.child});

  @override
  State<_ServerIcon> createState() => _ServerIconState();
}

class _ServerIconState extends State<_ServerIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedScale(
          scale: _hovered ? 1.1 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Green status bar shown in the sidebar when the user is in a voice call
/// but has navigated away to a text channel.
class _VoiceConnectedBar extends StatelessWidget {
  final String channelId;
  final VoidCallback onDisconnect;
  final VoidCallback onReturn;

  const _VoiceConnectedBar({
    required this.channelId,
    required this.onDisconnect,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final channelList = context
        .watch<ChannelProvider>()
        .voiceChannels
        .where((c) => c.id == channelId)
        .toList();
    final name = channelList.isNotEmpty ? channelList.first.name : 'Voice';
    return InkWell(
      onTap: onReturn,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.serverBar,
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.volume_up_rounded,
              size: 16,
              color: AppColors.online,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Voice Connected',
                    style: TextStyle(
                      color: AppColors.online,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Disconnect',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: onDisconnect,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.phone_disabled_rounded,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
