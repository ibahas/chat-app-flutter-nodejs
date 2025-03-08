import 'dart:async';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/websocket_service.dart';

class ChatService {
  final WebSocketService _socketService = WebSocketService();

  // Initialize connection
  Future<void> initialize() async {
    await _socketService.initialize();
  }

  // Get user groups
  Future<List<GroupModel>> getUserGroups(String userId) async {
    final response =
        await _socketService.emitWithAck('getUserGroups', {'userId': userId});

    if (response['success']) {
      return (response['data'] as List)
          .map((group) => GroupModel.fromJson(group))
          .toList();
    } else {
      throw Exception(response['message'] ?? 'Failed to fetch user groups');
    }
  }

  // Create a new group
  Future<void> createGroup({
    required String name,
    required String adminId,
    required List<String> memberIds,
  }) async {
    final response = await _socketService.emitWithAck('createGroup', {
      'name': name,
      'adminId': adminId,
      'members': memberIds,
    });

    if (!response['success']) {
      throw Exception(response['message'] ?? 'Failed to create group');
    }
  }

  // Get group messages as a stream
  Stream<List<MessageModel>> getGroupMessages(String groupId) {
    final controller = StreamController<List<MessageModel>>();

    // Subscribe to messages for this specific group
    _socketService.listen('groupMessages:$groupId', (data) {
      final messages =
          (data as List).map((msg) => MessageModel.fromJson(msg)).toList();
      controller.add(messages);
    });

    // Request initial messages
    _socketService.emit('joinGroup', {'groupId': groupId});

    // Clean up on stream close
    controller.onCancel = () {
      _socketService.off('groupMessages:$groupId');
      _socketService.emit('leaveGroup', {'groupId': groupId});
    };

    return controller.stream;
  }

  // Send a message to a group
  Future<void> sendGroupMessage({
    required String groupId,
    required MessageModel message,
  }) async {
    final response =
        await _socketService.emitWithAck('sendGroupMessageRealTime', {
      'groupId': groupId,
      'message': message.toMap(),
    });

    if (!response['success']) {
      throw Exception(response['message'] ?? 'Failed to send message');
    }
  }

  void disconnect() {
    _socketService.disconnect();
  }
}
