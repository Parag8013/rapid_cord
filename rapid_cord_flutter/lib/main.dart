import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/message.dart';
import 'providers/call_provider.dart';
import 'providers/channel_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/media_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/user_provider.dart';
import 'screens/main_layout.dart';
import 'screens/auth_screen.dart';
import 'screens/voice_channel_screen.dart';
import 'services/pop_out_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'widgets/notification_overlay.dart';

/// Unidirectional channel: only the main window registers; any window invokes.
const _mainWindowChannel = WindowMethodChannel(
  'rapid_cord/main_window',
  mode: ChannelMode.unidirectional,
);

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detect if this is a secondary window FIRST — secondary windows must not
  // register the main-window channel handler (unidirectional channels only
  // allow one registered handler engine-wide; a second registration throws
  // CHANNEL_LIMIT_REACHED and causes a white screen).
  try {
    final windowController = await WindowController.fromCurrentEngine();
    final argumentString = windowController.arguments;

    if (argumentString.isNotEmpty) {
      Map<String, dynamic> arguments;
      try {
        arguments = jsonDecode(argumentString) as Map<String, dynamic>;
      } catch (_) {
        arguments = {};
      }
      runApp(
        PopOutApp(windowId: windowController.windowId, arguments: arguments),
      );
      return;
    }
  } catch (e) {
    // Main window on some platforms — fall through to normal launch.
    debugPrint('[main] fromCurrentEngine failed (expected on main): $e');
  }

  // Main window only: listen for messages from secondary (pop-out) windows.
  await _mainWindowChannel.setMethodCallHandler((call) async {
    if (call.method == 'popOutClosed') {
      PopOutService.instance.handlePopOutClosed();
    } else if (call.method == 'handoffBack') {
      // Pop-out is transferring the call back to the main window.
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
      PopOutService.instance.handlePopOutClosed();
      PopOutService.instance.signalHandoffBack(args);
    }
    return null;
  });

  // Main application window
  runApp(const RapidCordApp());
}

class RapidCordApp extends StatelessWidget {
  const RapidCordApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ChannelProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => MediaProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => CallProvider()),
        ChangeNotifierProvider.value(value: PopOutService.instance),
      ],
      child: MaterialApp(
        title: 'RapidCord',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const _AppRoot(),
      ),
    );
  }
}

/// Loads the saved JWT session and gates entry to the main app.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  /// Returns true if the JWT has passed its `exp` claim (or is malformed).
  bool _jwtIsExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      var payload = parts[1];
      final mod4 = payload.length % 4;
      if (mod4 != 0) payload += '=' * (4 - mod4);
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = map['exp'] as int?;
      if (exp == null) return false;
      return DateTime.now().isAfter(
        DateTime.fromMillisecondsSinceEpoch(exp * 1000),
      );
    } catch (_) {
      return true;
    }
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    final username = prefs.getString('username') ?? '';
    final userId = prefs.getString('user_id') ?? '';

    if (!mounted) return;

    if (token.isNotEmpty && _jwtIsExpired(token)) {
      // Stored token is expired — wipe it so the user sees the login screen.
      debugPrint('[AppRoot] Stored JWT expired — clearing session');
      await prefs.remove('jwt_token');
      await prefs.remove('username');
      await prefs.remove('user_id');
    } else if (token.isNotEmpty) {
      context.read<UserProvider>().setSession(
        username: username,
        jwtToken: token,
        userId: userId,
      );
      context.read<CallProvider>().configure(
        serverUrl: 'ws://80.225.229.226:8080/ws',
        userId: userId,
        jwtToken: token,
      );
      context.read<ChannelProvider>().startPresencePolling(
        'http://80.225.229.226:8080',
        token,
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  void _onAuthenticated(String userId, String username, String jwtToken) {
    // UserProvider is already hydrated by AuthScreen before this callback fires.
    // Rebuilding is automatic because UserProvider notifies its listeners.
    context.read<CallProvider>().configure(
      serverUrl: 'ws://80.225.229.226:8080/ws',
      userId: userId,
      jwtToken: jwtToken,
    );
    context.read<ChannelProvider>().startPresencePolling(
      'http://80.225.229.226:8080',
      jwtToken,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.serverBar,
        body: Center(child: CircularProgressIndicator(color: AppColors.purple)),
      );
    }
    // React to UserProvider changes (login AND logout) without local state.
    if (!context.watch<UserProvider>().isAuthenticated) {
      return AuthScreen(onAuthenticated: _onAuthenticated);
    }
    return const Stack(
      children: [MainLayoutWithHandoff(), NotificationOverlay()],
    );
  }
}

/// The standalone app run inside the secondary pop-out OS window.
class PopOutApp extends StatelessWidget {
  final String windowId;
  final Map<String, dynamic> arguments;

  const PopOutApp({super.key, required this.windowId, required this.arguments});

  @override
  Widget build(BuildContext context) {
    // Mark this engine as the secondary window so UI adapts (e.g., the
    // pop-out button in MediaControls is hidden).
    PopOutService.isSecondaryWindow = true;

    final channelId = arguments['channelId'] as String? ?? 'vc-1';
    final channelName = arguments['channelName'] as String? ?? 'Voice Call';
    final userId = arguments['userId'] as String? ?? '';
    final username = arguments['username'] as String? ?? userId;
    final jwtToken = arguments['jwtToken'] as String? ?? '';
    final serverUrl = arguments['serverUrl'] as String? ?? '';
    final isHandoff = arguments['isHandoff'] as bool? ?? false;
    final rawHistory = arguments['chatHistory'] as List<dynamic>? ?? [];
    final chatHistory = rawHistory
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => MediaProvider()),
        ChangeNotifierProvider(create: (_) => CallProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        title: 'RapidCord — $channelName',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: _PopOutRoot(
          windowId: windowId,
          channelId: channelId,
          channelName: channelName,
          userId: userId,
          username: username,
          jwtToken: jwtToken,
          serverUrl: serverUrl,
          isHandoff: isHandoff,
          chatHistory: chatHistory,
        ),
      ),
    );
  }
}

class _PopOutRoot extends StatefulWidget {
  final String windowId;
  final String channelId;
  final String channelName;
  final String userId; // numeric sub from JWT
  final String username; // human-readable display name
  final String jwtToken;
  final String serverUrl;
  final bool isHandoff;
  final List<ChatMessage> chatHistory;

  const _PopOutRoot({
    required this.windowId,
    required this.channelId,
    required this.channelName,
    required this.userId,
    required this.username,
    required this.jwtToken,
    required this.serverUrl,
    this.isHandoff = false,
    this.chatHistory = const [],
  });

  @override
  State<_PopOutRoot> createState() => _PopOutRootState();
}

class _PopOutRootState extends State<_PopOutRoot> {
  @override
  void initState() {
    super.initState();

    // Listen for close requests from the main window.
    WindowController.fromWindowId(widget.windowId).setWindowMethodHandler((
      call,
    ) async {
      if (call.method == 'closeRequest' && mounted) {
        await _close();
      }
      return null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.userId.isNotEmpty) {
        context.read<UserProvider>().setSession(
          username: widget.username,
          jwtToken: widget.jwtToken,
          userId: widget.userId,
        );
        context.read<CallProvider>().configure(
          serverUrl: widget.serverUrl,
          userId: widget.userId,
          jwtToken: widget.jwtToken,
        );
      }
      // Pre-seed chat history so the side panel shows existing messages.
      if (widget.chatHistory.isNotEmpty) {
        final chatProv = context.read<ChatProvider>();
        final voiceChatId = '${widget.channelId}-voice';
        for (final msg in widget.chatHistory) {
          chatProv.addMessage(voiceChatId, msg);
        }
      }
      context.read<MediaProvider>().joinVoiceChannel();
      final mediaProv = context.read<MediaProvider>();
      if (widget.isHandoff) {
        // Completing the handoff: reconnect with ?handoff=true so the server
        // skips the join broadcast and sends handoff_resume to existing peers.
        await context.read<CallProvider>().handoffJoin(
          widget.channelId,
          audioInputDeviceId: mediaProv.audioInputDeviceId,
          audioOutputDeviceId: mediaProv.audioOutputDeviceId,
        );
      } else {
        await context.read<CallProvider>().joinCall(
          widget.channelId,
          audioInputDeviceId: mediaProv.audioInputDeviceId,
          audioOutputDeviceId: mediaProv.audioOutputDeviceId,
        );
      }
    });
  }

  Future<void> _close() async {
    if (!mounted) return;
    final callProv = context.read<CallProvider>();
    final mediaProv = context.read<MediaProvider>();

    // Reverse handoff: transfer the call back to the main window before
    // closing this isolate.
    await callProv.sendHandoffStart();
    mediaProv.leaveVoiceChannel();

    // Tell the main window to complete the reverse handoff by rejoining.
    try {
      await _mainWindowChannel.invokeMethod('handoffBack', {
        'channelId': widget.channelId,
        'channelName': widget.channelName,
        'userId': widget.userId,
        'serverUrl': widget.serverUrl,
      });
    } catch (_) {}

    try {
      await WindowController.fromWindowId(widget.windowId).hide();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.serverBar,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Column(
          children: [
            // ── Custom title bar ──────────────────────────────────────────
            Container(
              height: 36,
              color: AppColors.contentBg,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.picture_in_picture_alt_rounded,
                    size: 14,
                    color: AppColors.purple,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.channelName,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Text(
                    'Pop-out  •',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Close pop-out and return to main window',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _close,
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Full voice channel screen ─────────────────────────────────
            Expanded(
              child: VoiceChannelScreen(
                channelId: widget.channelId,
                channelName: widget.channelName,
                autoJoin: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
