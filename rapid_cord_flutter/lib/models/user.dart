import 'package:flutter/material.dart';

/// Represents a user in the app.
class User {
  final String id;
  final String displayName;
  final bool isMuted;
  final bool isDeafened;
  final bool isCameraOn;
  final bool isScreenSharing;
  final int avatarColorValue;
  final bool isOnline;

  const User({
    required this.id,
    required this.displayName,
    this.isMuted = false,
    this.isDeafened = false,
    this.isCameraOn = false,
    this.isScreenSharing = false,
    this.avatarColorValue = 0xFF7B61FF,
    this.isOnline = true,
  });

  Color get avatarColor => Color(avatarColorValue);

  User copyWith({
    String? id,
    String? displayName,
    bool? isMuted,
    bool? isDeafened,
    bool? isCameraOn,
    bool? isScreenSharing,
    int? avatarColorValue,
    bool? isOnline,
  }) {
    return User(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      isScreenSharing: isScreenSharing ?? this.isScreenSharing,
      avatarColorValue: avatarColorValue ?? this.avatarColorValue,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
