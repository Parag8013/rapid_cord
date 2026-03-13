/// Represents a chat message in a channel.
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final DateTime timestamp;
  final int avatarColorValue;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.timestamp,
    this.avatarColorValue = 0xFF7B61FF,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderName': senderName,
    'content': content,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'avatarColorValue': avatarColorValue,
  };

  /// Deserialise a locally-stored message (camelCase keys, ms timestamp).
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'].toString(),
    senderId: json['senderId'] as String,
    senderName: json['senderName'] as String,
    content: json['content'] as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
    avatarColorValue: json['avatarColorValue'] as int? ?? 0xFF7B61FF,
  );

  /// Deserialise a message returned by the Go REST API (snake_case keys,
  /// RFC-3339 timestamp string, integer id).
  factory ChatMessage.fromServerJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'].toString(),
    senderId: json['sender_id'] as String,
    senderName: json['sender_name'] as String,
    content: json['content'] as String,
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}
