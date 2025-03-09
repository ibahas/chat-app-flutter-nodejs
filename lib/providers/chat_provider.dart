import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/websocket_service.dart';

class ChatProvider with ChangeNotifier {
  final WebSocketService _socketService = WebSocketService();

  List<GroupModel> _userGroups = [];
  final List<MessageModel> _currentGroupMessages = [];
  bool _isLoading = false;
  String? _error;
  final StreamController<List<MessageModel>> _messageController =
      StreamController<List<MessageModel>>.broadcast();

  List<GroupModel> get userGroups => _userGroups;
  List<MessageModel> get currentGroupMessages => _currentGroupMessages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ChatProvider() {
    initialize();
  }

  //Initialization
  Future<void> initialize() async {
    try {
      _isLoading = true;
      notifyListeners();
      await _socketService.initialize();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshUserGroups(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Fetch latest user groups from the server
      await fetchUserGroups(userId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // ChatProvider.dart
  Future<void> fetchUserGroups(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();
      _userGroups = await _socketService
          .emitWithAck('getUserGroups', {'userId': userId}).then((response) {
        if (response['success']) {
          return (response['data'] as List)
              .map((group) => GroupModel.fromJson(group))
              .toList();
        } else {
          throw Exception(response['message'] ?? 'Failed to fetch user groups');
        }
      });
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  //Create group messages stream
  Stream<List<MessageModel>> groupMessagesStream(String groupId) {
    return _messageController.stream;
  }

  void onGroupMessageReceived(
      String groupId, Function(List<MessageModel>) onMessageReceived) {
    _socketService.listen('groupMessages:$groupId', (data) {
      // print('ChatProvider - onGroupMessageReceived - Event received for groupId: $groupId'); // ADD THIS LINE
      if (data is List) {
        final messages = data.map((msg) => MessageModel.fromJson(msg)).toList();
        // // print('ChatProvider - onGroupMessageReceived - Messages data:',
        //     messages); // ADD THIS LINE
        _messageController.add(messages); // Add messages to the stream
        onMessageReceived(messages);
      } else {
        // print('ChatProvider - onGroupMessageReceived - Unexpected data format: $data'); // ADD THIS LINE
      }
    });
  }

  void listenToGroupMessages(String groupId) {
    _socketService.emit('joinGroup', {'groupId': groupId});
  }

  //Remove User from group
  Future<bool> removeUserFromGroup(String groupId, String userId) async {
    // Return bool
    // print('removeUserFromGroup $groupId $userId');

    try {
      final response = await _socketService.emitWithAck('removeUserFromGroup', {
        'groupId': groupId,
        'userId': userId,
      });

      if (response['success'] == true) {
        return true; // Return true for success
      } else {
        throw Exception(
            response['message'] ?? 'Failed to remove user from group');
      }
    } catch (e) {
      // print('Error removing user from group: $e');
      return false; // Return false for failure
    }
  }

  //Add user from group
  Future<bool> addUserToGroup(String groupId, String userId) async {
    // Return bool
    // print('addUserToGroup $groupId $userId');

    try {
      final response = await _socketService.emitWithAck('addUserToGroup', {
        'groupId': groupId,
        'userId': userId,
      });
      // print('addUserToGroup response $response');
      if (response['success'] == true) {
        return true; // Return true for success
      } else {
        throw Exception(response['message'] ?? 'Failed to add user to group');
      }
    } catch (e) {
      // print('Error adding user to group: $e');
      return false; // Return false for failure
    }
  }

  //Update group name
  Future<bool> updateGroupName(
      // Keep method name as updateGroupName
      String groupId,
      Map<String, dynamic> updates) async {
    try {
      final response = await _socketService.emitWithAck('updateGroupName', {
        'groupId': groupId,
        ...updates,
      });

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to update group');
      }
    } catch (e) {
      // print('Error updating group: $e');
      return false;
    }
  }

  // Create a new group
  Future<void> createGroup({
    required String name,
    required String adminId,
    required List<String> memberIds,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();
      await _socketService.emitWithAck('createGroup', {
        'name': name,
        'adminId': adminId,
        'members': memberIds,
      });
      // After creating the group, refresh the user's group list
      await fetchUserGroups(adminId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Send a message to a group
  Future<void> sendGroupMessage({
    required String groupId,
    required String senderId,
    required String content,
    required MessageType type,
  }) async {
    try {
      MessageModel message = MessageModel(
          senderId: senderId,
          content: content,
          timestamp: DateTime.now(),
          type: type);

      _socketService.emit('sendGroupMessageRealTime', {
        'groupId': groupId,
        'message': message.toMap(),
      });
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
