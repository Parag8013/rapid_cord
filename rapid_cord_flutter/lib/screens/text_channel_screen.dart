import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/message_bubble.dart';

const _kServerHttpBase = 'http://80.225.229.226:8080';

/// Text channel view with chat messages and a message input bar.
class TextChannelScreen extends StatefulWidget {
  final String channelId;
  final String channelName;

  const TextChannelScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<TextChannelScreen> createState() => _TextChannelScreenState();
}

class _TextChannelScreenState extends State<TextChannelScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _initialized = false;

  late final AnimationController _enterController;
  late final Animation<double> _enterFade;
  late final Animation<Offset> _enterSlide;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _enterFade = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOutCubic,
    );
    _enterSlide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _enterController, curve: Curves.easeOutCubic),
        );
    _enterController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<ChatProvider>().fetchChannelHistory(
          widget.channelId,
          _kServerHttpBase,
        );
      });
    }
  }

  @override
  void dispose() {
    _enterController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final username = context.read<UserProvider>().username;
    final displayName = username.isEmpty ? 'User' : username;

    // postMessage persists to the server so messages survive app restarts.
    context.read<ChatProvider>().postMessage(
      channelId: widget.channelId,
      serverHttpBase: _kServerHttpBase,
      senderName: displayName,
      content: text,
    );
    _messageController.clear();

    // Scroll to bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _enterFade,
      child: SlideTransition(
        position: _enterSlide,
        child: Column(
          children: [
            // ── Channel Header ──
            _buildHeader(),

            // ── Messages ──
            Expanded(
              child: Consumer<ChatProvider>(
                builder: (context, chatProv, _) {
                  final messages = chatProv.getMessages(widget.channelId);
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(
                          milliseconds: 200 + (index * 50).clamp(0, 500),
                        ),
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

            // ── Message Input ──
            _buildMessageInput(),
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
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.tag, size: 22, color: AppColors.textMuted),
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
          _headerIcon(Icons.notifications_rounded),
          _headerIcon(Icons.push_pin_rounded),
          _headerIcon(Icons.people_rounded),
          const SizedBox(width: 8),
          // Search bar placeholder
          Container(
            width: 160,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppColors.serverBar,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Search',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ),
                Icon(Icons.search, size: 16, color: AppColors.textMuted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Icon(icon, size: 20, color: AppColors.textMuted),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.inputBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.add_circle_outline_rounded,
                color: AppColors.textMuted,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: InputDecoration(
                hintText: 'Message #${widget.channelName}',
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          _inputIcon(Icons.emoji_emotions_outlined),
          _inputIcon(Icons.gif_box_outlined),
        ],
      ),
    );
  }

  Widget _inputIcon(IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(icon, size: 22, color: AppColors.textMuted),
    );
  }
}
