import 'dart:async';
import 'dart:convert';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';
import '../models/message.dart';

/// Service for managing the voice-channel pop-out OS window.
///
/// Implements [ChangeNotifier] so the main-window UI can react to pop-out
/// state changes (show/hide the "popped out" banner).
class PopOutService extends ChangeNotifier {
  PopOutService._();
  static final PopOutService instance = PopOutService._();

  /// True when this Flutter engine is running inside the secondary pop-out
  /// window.  Set by [PopOutApp] before [runApp] so widgets can adapt
  /// (e.g., hide the pop-out button in MediaControls).
  static bool isSecondaryWindow = false;

  bool _isPopped = false;
  String? _windowId;

  bool get isPopped => _isPopped;
  String? get windowId => _windowId;

  /// Broadcast stream that fires when the pop-out window sends `handoffBack`
  /// via IPC. The main window should call [CallProvider.handoffJoin] on this.
  final _handoffBackController =
      StreamController<Map<String, String>>.broadcast();
  Stream<Map<String, String>> get onHandoffBack =>
      _handoffBackController.stream;

  /// Called from the main IPC handler when the pop-out requests a reverse
  /// handoff (pop-in back to the main window).
  void signalHandoffBack(Map<String, dynamic> args) {
    _handoffBackController.add({
      'channelId': args['channelId'] as String? ?? '',
      'channelName': args['channelName'] as String? ?? '',
      'userId': args['userId'] as String? ?? '',
      'serverUrl': args['serverUrl'] as String? ?? '',
    });
  }

  /// Open the voice-channel in a separate OS window using a connection handoff.
  ///
  /// The [jwtToken] is forwarded to the secondary engine so it can authenticate
  /// its WebSocket connection with the server.
  /// The [isHandoff] flag is forwarded to the secondary engine so it connects
  /// to the WebSocket with `?handoff=true`, completing the handoff sequence.
  /// [chatHistory] (optional) pre-seeds the pop-out's chat panel with existing
  /// messages so the user doesn't lose conversation context.
  Future<void> openPopOut({
    required String channelId,
    required String channelName,
    required String userId,
    required String username,
    required String jwtToken,
    required String serverUrl,
    bool isHandoff = false,
    List<ChatMessage> chatHistory = const [],
  }) async {
    if (_isPopped) {
      if (_windowId != null) {
        try {
          await WindowController.fromWindowId(_windowId!).show();
        } catch (_) {}
      }
      return;
    }
    try {
      final window = await WindowController.create(
        WindowConfiguration(
          arguments: jsonEncode({
            'type': 'voice_popout',
            'channelId': channelId,
            'channelName': channelName,
            'userId': userId,
            'username': username,
            'jwtToken': jwtToken,
            'serverUrl': serverUrl,
            'isHandoff': isHandoff,
            'chatHistory': chatHistory.map((m) => m.toJson()).toList(),
          }),
          hiddenAtLaunch: true,
        ),
      );
      await window.show();
      _windowId = window.windowId;
      _isPopped = true;
      notifyListeners();
      debugPrint(
        '[PopOutService] Pop-out opened: $_windowId (handoff=$isHandoff)',
      );
    } catch (e) {
      debugPrint('[PopOutService] Failed to create window: $e');
    }
  }

  /// Ask the pop-out window to close itself gracefully (normal close, no
  /// reverse handoff).
  Future<void> requestClose() async {
    if (_windowId == null) {
      handlePopOutClosed();
      return;
    }
    try {
      await WindowController.fromWindowId(
        _windowId!,
      ).invokeMethod('closeRequest');
    } catch (e) {
      debugPrint('[PopOutService] requestClose failed: $e');
      handlePopOutClosed();
    }
  }

  /// Called by the main window when the pop-out reports that it has closed.
  void handlePopOutClosed() {
    _windowId = null;
    _isPopped = false;
    notifyListeners();
    debugPrint('[PopOutService] Pop-out closed');
  }
}
