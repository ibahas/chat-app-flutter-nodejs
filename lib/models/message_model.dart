enum MessageType { text, voice, image }

class MessageModel {
  final String id;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final MessageType type;

  MessageModel({
    this.id = '',
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.type = MessageType.text,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] ?? '',
      senderId: json['senderId'] ?? '',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      type: _parseMessageType(json['type']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderId': senderId,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString().split('.').last,
    };
  }

  static MessageType _parseMessageType(String? typeStr) {
    if (typeStr == null) return MessageType.text;

    switch (typeStr) {
      case 'voice':
        return MessageType.voice;
      case 'image':
        return MessageType.image;
      default:
        return MessageType.text;
    }
  }
}
