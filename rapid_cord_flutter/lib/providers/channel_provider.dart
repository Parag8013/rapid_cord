import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/channel.dart';

/// Mock channel data matching the Discord reference screenshots.
final List<Channel> _mockChannels = [
  const Channel(id: 'tc-1', name: 'bot-stuffs', type: ChannelType.text),
  const Channel(id: 'tc-2', name: 'porashona', type: ChannelType.text),
  const Channel(id: 'tc-3', name: 'poribrajok', type: ChannelType.text),
  const Channel(id: 'tc-4', name: 'date-ideazz', type: ChannelType.text),
  const Channel(id: 'tc-5', name: 'resources', type: ChannelType.text),
  const Channel(id: 'tc-6', name: 'daily-target', type: ChannelType.text),
  const Channel(id: 'tc-7', name: 'reminders', type: ChannelType.text),
  const Channel(id: 'tc-8', name: 'bok-bok', type: ChannelType.text),
  const Channel(id: 'vc-1', name: 'General', type: ChannelType.voice),
];

/// Manages channel list and selection state.
class ChannelProvider extends ChangeNotifier {
  List<Channel> _channels = List.from(_mockChannels);
  Channel? _selectedChannel;
  Timer? _presenceTimer;

  ChannelProvider() {
    // Default to first text channel.
    _selectedChannel = _channels.first;
  }

  List<Channel> get channels => _channels;
  Channel? get selectedChannel => _selectedChannel;

  List<Channel> get textChannels =>
      _channels.where((c) => c.type == ChannelType.text).toList();

  List<Channel> get voiceChannels =>
      _channels.where((c) => c.type == ChannelType.voice).toList();

  void selectChannel(Channel channel) {
    _selectedChannel = channel;
    notifyListeners();
  }

  void updateChannels(List<Channel> channels) {
    _channels = channels;
    notifyListeners();
  }

  /// Start polling `GET /presence` every 5 seconds to keep voice channel
  /// occupancy up to date without requiring the local user to be in a call.
  void startPresencePolling(String serverHttpBase, String jwtToken) {
    _presenceTimer?.cancel();
    // Fetch immediately, then repeat every 5 seconds.
    _fetchPresence(serverHttpBase, jwtToken);
    _presenceTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchPresence(serverHttpBase, jwtToken);
    });
  }

  Future<void> _fetchPresence(String serverHttpBase, String jwtToken) async {
    try {
      final response = await http
          .get(
            Uri.parse('$serverHttpBase/presence'),
            headers: {'Authorization': 'Bearer $jwtToken'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return;

      final Map<String, dynamic> raw =
          jsonDecode(response.body) as Map<String, dynamic>? ?? {};

      // Convert to Map<String, List<String>>.
      final presence = raw.map(
        (roomId, value) => MapEntry(
          roomId,
          (value as List<dynamic>).map((e) => e as String).toList(),
        ),
      );

      var changed = false;
      final updated = _channels.map((ch) {
        if (ch.type != ChannelType.voice) return ch;
        final liveIds = presence[ch.id] ?? const <String>[];
        // Only rebuild if the list actually changed.
        if (_listEquals(ch.connectedUserIds, liveIds)) return ch;
        changed = true;
        return ch.copyWith(connectedUserIds: liveIds);
      }).toList();

      if (changed) {
        _channels = updated;
        // Keep selected channel reference in sync.
        if (_selectedChannel != null) {
          _selectedChannel = _channels.firstWhere(
            (c) => c.id == _selectedChannel!.id,
            orElse: () => _channels.first,
          );
        }
        notifyListeners();
      }
    } catch (_) {
      // Network errors are silently swallowed — the UI keeps stale data.
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }
}
