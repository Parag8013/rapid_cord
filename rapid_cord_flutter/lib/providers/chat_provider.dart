import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

/// Manages chat messages per channel.
class ChatProvider extends ChangeNotifier {
  final Map<String, List<ChatMessage>> _messages = {};
  // Tracks which channels have had their history fetched so we only fetch once.
  final Set<String> _fetched = {};

  /// Get messages for a specific channel.
  List<ChatMessage> getMessages(String channelId) {
    return _messages[channelId] ?? [];
  }

  /// Add a message to a channel.
  void addMessage(String channelId, ChatMessage message) {
    _messages.putIfAbsent(channelId, () => []);
    _messages[channelId]!.add(message);
    notifyListeners();
  }

  /// Send a message (local + signaling stub).
  void sendMessage({
    required String channelId,
    required String senderId,
    required String senderName,
    required String content,
    int avatarColor = 0xFF7B61FF,
  }) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: senderId,
      senderName: senderName,
      content: content,
      timestamp: DateTime.now(),
      avatarColorValue: avatarColor,
    );
    addMessage(channelId, message);
  }

  /// POST a message to the server, add it optimistically, then refresh history.
  ///
  /// Use this for text channels where messages must survive app restarts.
  Future<void> postMessage({
    required String channelId,
    required String serverHttpBase,
    required String senderName,
    required String content,
  }) async {
    // Optimistic local add so the user sees the message immediately.
    final tempId = 'local-${DateTime.now().millisecondsSinceEpoch}';
    final tempMsg = ChatMessage(
      id: tempId,
      senderId: 'local-user',
      senderName: senderName,
      content: content,
      timestamp: DateTime.now(),
      avatarColorValue: 0xFF7B61FF,
    );
    addMessage(channelId, tempMsg);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      if (token.isEmpty) return;

      final url = Uri.parse('$serverHttpBase/channels/$channelId/messages');
      final response = await http
          .post(
            url,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'content': content, 'sender_name': senderName}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 201) {
        debugPrint(
          '[ChatProvider] postMessage $channelId → ${response.statusCode}',
        );
        return;
      }

      // Replace optimistic message with the server-authoritative version.
      _messages[channelId]?.removeWhere((m) => m.id == tempId);
      _fetched.remove(channelId); // force re-fetch to get server-assigned IDs
      await fetchChannelHistory(channelId, serverHttpBase);
    } catch (e) {
      debugPrint('[ChatProvider] postMessage error: $e');
      // Keep the optimistic message visible so the user sees their text.
    }
  }

  /// Receive a message from the signaling service.
  void receiveMessage(String channelId, ChatMessage message) {
    addMessage(channelId, message);
  }

  /// Fetch message history from the server for [channelId].
  ///
  /// Reads the JWT from SharedPreferences and calls
  /// `GET http://<serverHttpBase>/channels/<channelId>/messages`.
  /// [serverHttpBase] should be e.g. `http://80.225.229.226:8080`.
  /// No-ops if history has already been fetched this session.
  Future<void> fetchChannelHistory(
    String channelId,
    String serverHttpBase,
  ) async {
    if (_fetched.contains(channelId)) return;
    _fetched.add(channelId);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      if (token.isEmpty) return;

      final url = Uri.parse('$serverHttpBase/channels/$channelId/messages');
      final response = await http
          .get(url, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        _fetched.remove(channelId);
        return;
      }

      final List<dynamic> raw =
          jsonDecode(response.body) as List<dynamic>? ?? [];
      final fetched = raw
          .map((e) => ChatMessage.fromServerJson(e as Map<String, dynamic>))
          .toList();

      if (fetched.isNotEmpty) {
        final existing = _messages[channelId] ?? [];
        final existingIds = existing.map((m) => m.id).toSet();
        final newMessages = fetched
            .where((m) => !existingIds.contains(m.id))
            .toList();

        if (newMessages.isNotEmpty) {
          // Append then sort chronologically so history always reads oldest→newest.
          _messages[channelId] = [...existing, ...newMessages];
          _messages[channelId]!.sort(
            (a, b) => a.timestamp.compareTo(b.timestamp),
          );
          notifyListeners();
        }
      }
    } catch (e) {
      _fetched.remove(channelId);
    }
  }
}
