import 'package:flutter/material.dart';

/// The type of channel.
enum ChannelType { text, voice }

/// Represents a server channel (text or voice).
class Channel {
  final String id;
  final String name;
  final ChannelType type;
  final IconData icon;
  final List<String> connectedUserIds;

  const Channel({
    required this.id,
    required this.name,
    required this.type,
    IconData? icon,
    this.connectedUserIds = const [],
  }) : icon =
           icon ??
           (type == ChannelType.text ? Icons.tag : Icons.volume_up_rounded);

  Channel copyWith({
    String? id,
    String? name,
    ChannelType? type,
    IconData? icon,
    List<String>? connectedUserIds,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      connectedUserIds: connectedUserIds ?? this.connectedUserIds,
    );
  }
}
