import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/call_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/media_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/media_controls.dart';
import '../widgets/message_bubble.dart';
import '../widgets/quality_settings_panel.dart';
import '../widgets/video_tile.dart';

/// Voice channel view with video grid, side chat, and media controls.
///
/// Features:
/// - Animated PIP mode transitions (focus/unfocus tiles)
/// - Animated side chat panel (slide in/out)
/// - Smooth fade transitions on enter
class VoiceChannelScreen extends StatefulWidget {
  final String channelId;
  final String channelName;

  /// When false the screen skips its own joinCall / joinVoiceChannel logic.
  /// Set to false when the parent (e.g. _PopOutRoot) handles joining.
  final bool autoJoin;

  const VoiceChannelScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.autoJoin = true,
  });

  @override
  State<VoiceChannelScreen> createState() => _VoiceChannelScreenState();
}

class _VoiceChannelScreenState extends State<VoiceChannelScreen>
    with TickerProviderStateMixin {
  bool _showSideChat = true;
  int? _focusedTileIndex;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _initialized = false;
  StreamSubscription? _incomingChatSub;
  // Saved for use in dispose (can't use context there).
  MediaProvider? _mediaProvider;
  CallProvider? _callProvider;

  // Track previous media toggle states to detect changes.
  bool _prevMuted = false;
  bool _prevCameraOn = false;
  bool _prevIsScreenSharing = false;
  bool _prevPushToTalk = false;

  // ── Push-to-talk ──
  bool _pttHandlerAdded = false;

  // ── Animations ──
  late final AnimationController _enterController;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;

  late final AnimationController _pipController;
  late final Animation<double> _pipFade;

  late final AnimationController _chatPanelController;
  late final Animation<Offset> _chatPanelSlide;
  late final Animation<double> _chatPanelFade;

  @override
  void initState() {
    super.initState();

    // Enter animation.
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _enterFade = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOutCubic,
    );
    _enterSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
        );

    // PIP transition animation.
    _pipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _pipFade = CurvedAnimation(
      parent: _pipController,
      curve: Curves.easeInOutCubic,
    );

    // Side-chat slide animation (starts open).
    _chatPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _showSideChat ? 1.0 : 0.0,
    );
    _chatPanelSlide =
        Tween<Offset>(begin: const Offset(1.0, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _chatPanelController,
            curve: Curves.easeOutCubic,
          ),
        );
    _chatPanelFade = CurvedAnimation(
      parent: _chatPanelController,
      curve: Curves.easeIn,
    );

    _enterController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _mediaProvider = context.read<MediaProvider>();
      _callProvider = context.read<CallProvider>();
      _callProvider!.addListener(_onCallProviderChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final chatProv = context.read<ChatProvider>();
        // If already connected to this channel, skip re-joining.
        if (!widget.autoJoin ||
            (_callProvider!.isInCall &&
                _callProvider!.currentChannelId == widget.channelId)) {
          _resubscribeChat(chatProv);
          return;
        }
        _mediaProvider!.joinVoiceChannel();
        await _callProvider!.joinCall(
          widget.channelId,
          qualitySettings: _mediaProvider!.qualitySettings,
          audioInputDeviceId: _mediaProvider!.audioInputDeviceId,
          audioOutputDeviceId: _mediaProvider!.audioOutputDeviceId,
        );
        _resubscribeChat(chatProv);
        final voiceChatId = '${widget.channelId}-voice';
        chatProv.fetchChannelHistory(voiceChatId, 'http://80.225.229.226:8080');
      });
    }
  }

  void _resubscribeChat(ChatProvider chatProv) {
    _incomingChatSub?.cancel();
    _incomingChatSub = _callProvider!.onIncomingChat.listen((event) {
      // event.channelId already contains the full channel ID (e.g. "vc-1-voice")
      // as sent in the WebSocket payload — do not append -voice again.
      chatProv.addMessage(event.channelId, event.message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _onCallProviderChanged() {
    if (!mounted) return;
    final callProv = _callProvider!;
    if (callProv.isScreenSharing != _prevIsScreenSharing) {
      _prevIsScreenSharing = callProv.isScreenSharing;
      if (callProv.isScreenSharing) {
        final tiles = _buildParticipantList(callProv);
        setState(() => _focusedTileIndex = tiles.length - 1);
      } else {
        setState(() => _focusedTileIndex = null);
      }
    }
  }

  // ── PTT ──────────────────────────────────────────────────────────────────

  void _syncPttHandler({required bool enable}) {
    if (enable == _pttHandlerAdded) return;
    if (enable) {
      HardwareKeyboard.instance.addHandler(_handlePttKey);
      // Ensure mic starts muted when PTT first activates.
      _callProvider?.setMicEnabled(false);
      _pttHandlerAdded = true;
    } else {
      HardwareKeyboard.instance.removeHandler(_handlePttKey);
      _pttHandlerAdded = false;
    }
  }

  bool _handlePttKey(KeyEvent event) {
    final qs = _mediaProvider?.qualitySettings;
    if (qs == null || !qs.pushToTalk) return false;

    final expectedLabel = qs.pushToTalkKey;
    final keyLabel = event.logicalKey.keyLabel.isEmpty
        ? (event.logicalKey.debugName ?? '')
        : event.logicalKey.keyLabel;
    if (keyLabel != expectedLabel) return false;

    if (event is KeyDownEvent) {
      _callProvider?.setMicEnabled(true);
    } else if (event is KeyUpEvent) {
      _callProvider?.setMicEnabled(false);
    }
    return false; // don't consume — allow other listeners (e.g. keyboard shortcuts)
  }

  @override
  void dispose() {
    _callProvider?.removeListener(_onCallProviderChanged);
    _incomingChatSub?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    _enterController.dispose();
    _pipController.dispose();
    _chatPanelController.dispose();
    if (_pttHandlerAdded) {
      HardwareKeyboard.instance.removeHandler(_handlePttKey);
    }
    super.dispose();
  }

  void _onTileTap(int index) {
    setState(() {
      if (_focusedTileIndex == index) {
        _focusedTileIndex = null;
        _pipController.reverse();
      } else {
        _focusedTileIndex = index;
        _pipController.forward(from: 0.0);
      }
    });
  }

  void _sendVoiceChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    final username = context.read<UserProvider>().username;
    final displayName = username.isEmpty ? 'User' : username;

    context.read<ChatProvider>().sendMessage(
      channelId: '${widget.channelId}-voice',
      senderId: 'local-user',
      senderName: displayName,
      content: text,
      avatarColor: 0xFF7B61FF,
    );
    // Also broadcast to the remote peer via signaling.
    // Use the same -voice suffix so hub.go saves under the same channel ID
    // that fetchChannelHistory will query.
    context.read<CallProvider>().sendChatMessage(
      channelId: '${widget.channelId}-voice',
      content: text,
      senderName: displayName,
    );
    _chatController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _enterFade,
      child: SlideTransition(
        position: _enterSlide,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _buildVideoArea()),
                  // Animated side chat panel — slides in from the right.
                  ClipRect(
                    child: SizeTransition(
                      axis: Axis.horizontal,
                      sizeFactor: CurvedAnimation(
                        parent: _chatPanelController,
                        curve: Curves.easeInOutCubic,
                      ),
                      child: SlideTransition(
                        position: _chatPanelSlide,
                        child: FadeTransition(
                          opacity: _chatPanelFade,
                          child: _buildSideChat(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            MediaControls(
              channelId: widget.channelId,
              channelName: widget.channelName,
              onHangUp: () {
                context.read<CallProvider>().leaveCall();
                context.read<MediaProvider>().leaveVoiceChannel();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.contentBg,
        border: Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          Icon(Icons.volume_up_rounded, size: 22, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Text(
            widget.channelName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const Spacer(),
          // Quality settings
          Tooltip(
            message: 'Stream Quality',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => showQualitySettingsPanel(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Toggle side chat
          Tooltip(
            message: _showSideChat ? 'Hide Chat' : 'Show Chat',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                setState(() => _showSideChat = !_showSideChat);
                if (_showSideChat) {
                  _chatPanelController.forward();
                } else {
                  _chatPanelController.reverse();
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: _showSideChat
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    final isPipMode = _focusedTileIndex != null;

    return Consumer<CallProvider>(
      builder: (context, callProv, _) {
        // Forward media toggle changes to actual WebRTC tracks.
        final mediaProv = context.watch<MediaProvider>();

        // Sync PTT keyboard handler when the setting is toggled.
        final pttEnabled = mediaProv.qualitySettings.pushToTalk;
        if (pttEnabled != _prevPushToTalk) {
          _prevPushToTalk = pttEnabled;
          _syncPttHandler(enable: pttEnabled);
        }

        if (mediaProv.isMuted != _prevMuted) {
          _prevMuted = mediaProv.isMuted;
          // In PTT mode the keyboard handler owns mic gating — skip normal sync.
          if (!pttEnabled) {
            callProv.setMicEnabled(!mediaProv.isMuted);
          }
        }
        if (mediaProv.isCameraOn != _prevCameraOn) {
          _prevCameraOn = mediaProv.isCameraOn;
          callProv.setCameraEnabled(mediaProv.isCameraOn);
        }

        return Container(
          color: AppColors.serverBar,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: isPipMode
                ? _buildPipView(key: const ValueKey('pip'), callProv: callProv)
                : _buildGridView(
                    key: const ValueKey('grid'),
                    callProv: callProv,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildPipView({Key? key, required CallProvider callProv}) {
    // Build list of tiles: local (index 0) + remote (index 1, if connected)
    final tiles = _buildParticipantList(callProv);
    if (_focusedTileIndex! >= tiles.length) {
      // Focused index out of range — reset
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _focusedTileIndex = null);
      });
      return const SizedBox.shrink();
    }
    final focused = tiles[_focusedTileIndex!];

    return Stack(
      key: key,
      children: [
        // Focused tile — fullscreen.
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FadeTransition(
              opacity: _pipFade,
              child: VideoTile(
                participantName: focused['name'] as String,
                renderer: focused['renderer'] as RTCVideoRenderer?,
                mirror: focused['mirror'] as bool? ?? false,
                isSpeaking: focused['speaking'] as bool? ?? false,
                onTap: () => _onTileTap(_focusedTileIndex!),
              ),
            ),
          ),
        ),
        // Mini tiles for others.
        ..._buildMiniTiles(callProv),
      ],
    );
  }

  Widget _buildGridView({Key? key, required CallProvider callProv}) {
    final hasOthers = callProv.hasRemoteStream || callProv.isScreenSharing;
    final tiles = _buildParticipantList(callProv);

    return Padding(
      key: key,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = tiles.length;
            final crossAxisCount = count <= 2 ? count : 2;
            return Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 16 / 9,
                    ),
                    itemCount: count,
                    itemBuilder: (context, index) {
                      final tile = tiles[index];
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 300 + (index * 100)),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.scale(
                              scale: 0.9 + (0.1 * value),
                              child: child,
                            ),
                          );
                        },
                        child: VideoTile(
                          participantName: tile['name'] as String,
                          renderer: tile['renderer'] as RTCVideoRenderer?,
                          mirror: tile['mirror'] as bool? ?? false,
                          isMuted: tile['muted'] as bool? ?? false,
                          isSpeaking: tile['speaking'] as bool? ?? false,
                          onTap: () => _onTileTap(index),
                        ),
                      );
                    },
                  ),
                ),
                if (!hasOthers) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'No one else is in the voice channel',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Invite others or wait for someone to join.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Build the participant list from live CallProvider state.
  /// Index 0 = local camera, Index 1 = remote peer (if connected),
  /// Index 2 = own screen share (if active).
  List<Map<String, dynamic>> _buildParticipantList(CallProvider callProv) {
    final localName = context.read<UserProvider>().username;
    final list = <Map<String, dynamic>>[
      {
        'name': localName.isNotEmpty ? localName : 'You',
        'renderer': callProv.isInCall ? callProv.localRenderer : null,
        'mirror': true,
        'muted': context.read<MediaProvider>().isMuted,
        'speaking': callProv.isLocalSpeaking,
      },
    ];
    if (callProv.hasRemoteStream) {
      final remoteName = callProv.remotePeerName;
      list.add({
        'name': (remoteName != null && remoteName.isNotEmpty)
            ? remoteName
            : 'Peer',
        'renderer': callProv.remoteRenderer,
        'mirror': false,
        'muted': false,
        'speaking': callProv.isRemoteSpeaking,
      });
    }
    if (callProv.isScreenSharing) {
      list.add({
        'name': 'Your Screen',
        'renderer': callProv.screenRenderer,
        'mirror': false,
        'muted': true,
        'speaking': false,
      });
    }
    if (callProv.isRemoteScreenSharing) {
      list.add({
        'name': "${callProv.remotePeerName ?? 'Peer'}'s Screen",
        'renderer': callProv.remoteScreenRenderer,
        'mirror': false,
        'muted': true,
        'speaking': false,
      });
    }
    return list;
  }

  List<Widget> _buildMiniTiles(CallProvider callProv) {
    final tiles = _buildParticipantList(callProv);
    final miniParticipants = <int>[];
    for (int i = 0; i < tiles.length; i++) {
      if (i != _focusedTileIndex) {
        miniParticipants.add(i);
      }
    }

    return miniParticipants.asMap().entries.map((entry) {
      final offset = entry.key;
      final participantIdx = entry.value;
      final tile = tiles[participantIdx];
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        top: 16 + (offset * 110.0),
        left: 16,
        width: 140,
        height: 100,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: VideoTile(
            participantName: tile['name'] as String,
            renderer: tile['renderer'] as RTCVideoRenderer?,
            mirror: tile['mirror'] as bool? ?? false,
            isMini: true,
            isMuted: tile['muted'] as bool? ?? false,
            isSpeaking: tile['speaking'] as bool? ?? false,
            onTap: () => _onTileTap(participantIdx),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSideChat() {
    final voiceChatId = '${widget.channelId}-voice';
    return SizedBox(
      width: 340,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.contentBg,
          border: Border(left: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: Column(
          children: [
            // Chat header
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.divider, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.channelName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      setState(() => _showSideChat = false);
                      _chatPanelController.reverse();
                    },
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

            // Messages
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProv, _) {
                  final messages = chatProv.getMessages(voiceChatId);
                  return ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 200 + (index * 50)),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(20 * (1 - value), 0),
                              child: child,
                            ),
                          );
                        },
                        child: MessageBubble(message: messages[index]),
                      );
                    },
                  );
                },
              ),
            ),

            // Chat input
            Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.inputBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () {},
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Message ${widget.channelName}',
                        hintStyle: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: (_) => _sendVoiceChat(),
                    ),
                  ),
                  const Icon(
                    Icons.emoji_emotions_outlined,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.grid_view_rounded,
                    size: 20,
                    color: AppColors.textMuted,
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
