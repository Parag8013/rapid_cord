import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sound_service.dart';

/// Represents a single in-app notification.
class AppNotification {
  final String id;
  final String title;
  final String body;
  final IconData icon;
  final DateTime timestamp;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.icon = Icons.notifications_rounded,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Manages in-app notification state.
class NotificationProvider extends ChangeNotifier {
  bool _enabled = true;
  final List<AppNotification> _notifications = [];
  final Map<String, Timer> _dismissTimers = {};

  bool get enabled => _enabled;
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  void toggleEnabled() {
    _enabled = !_enabled;
    notifyListeners();
  }

  /// Show a notification pop-up with auto-dismiss after [duration].
  void showNotification({
    required String title,
    required String body,
    IconData icon = Icons.notifications_rounded,
    Duration duration = const Duration(seconds: 4),
  }) {
    if (!_enabled) return;

    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      icon: icon,
    );

    _notifications.add(notification);
    SoundService.instance.play(SoundEffect.notification);
    notifyListeners();

    // Auto-dismiss.
    _dismissTimers[notification.id] = Timer(duration, () {
      dismissNotification(notification.id);
    });
  }

  /// Dismiss a notification by ID.
  void dismissNotification(String id) {
    _dismissTimers[id]?.cancel();
    _dismissTimers.remove(id);
    _notifications.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  /// Clear all notifications.
  void clearAll() {
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    _dismissTimers.clear();
    _notifications.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final timer in _dismissTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
