// admin_service.dart
import '../models/user_model.dart';
import '../models/group_model.dart';
import './websocket_service.dart';

class AdminService {
  final WebSocketService _webSocketService = WebSocketService();

  // Initialize the service
  Future<void> initialize() async {
    await _webSocketService.initialize();
  }

  // Get all users
  Future<List<UserModel>> getAllUsers() async {
    try {
      final response =
          await _webSocketService.emitWithAck('admin:getAllUsers', {});

      if (response['success'] == true && response['data'] != null) {
        return (response['data'] as List)
            .map((userData) => UserModel.fromJson(userData))
            .where((user) => user.role != UserRole.admin)
            .toList();
      } else {
        throw Exception(response['message'] ?? 'Failed to get users');
      }
    } catch (e) {
      // print('Error getting all users: $e');
      throw Exception('Failed to retrieve users: $e');
    }
  }

  // Block a user
  Future<void> blockUser(String userId) async {
    try {
      final response = await _webSocketService
          .emitWithAck('admin:blockUser', {'userId': userId});

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to block user');
      }
    } catch (e) {
      // print('Error blocking user: $e');
      throw Exception('Failed to block user: $e');
    }
  }

  // Unblock a user
  Future<void> unblockUser(String userId) async {
    try {
      final response = await _webSocketService
          .emitWithAck('admin:unblockUser', {'userId': userId});

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to unblock user');
      }
    } catch (e) {
      // print('Error unblocking user: $e');
      throw Exception('Failed to unblock user: $e');
    }
  }

  // Get all groups
  Future<List<GroupModel>> getAllGroups() async {
    try {
      final response =
          await _webSocketService.emitWithAck('admin:getAllGroups', {});

      if (response['success'] == true && response['data'] != null) {
        return (response['data'] as List)
            .map((groupData) => GroupModel.fromJson(groupData))
            .toList();
      } else {
        throw Exception(response['message'] ?? 'Failed to get groups');
      }
    } catch (e) {
      // print('Error getting all groups: $e');
      throw Exception('Failed to retrieve groups: $e');
    }
  }

  // Delete a group
  Future<void> deleteGroup(String groupId) async {
    try {
      final response = await _webSocketService
          .emitWithAck('admin:deleteGroup', {'groupId': groupId});

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to delete group');
      }
    } catch (e) {
      // print('Error deleting group: $e');
      throw Exception('Failed to delete group: $e');
    }
  }

  // Listen for user updates (optional real-time functionality)
  void listenForUserUpdates(Function(UserModel) callback) {
    _webSocketService.listen('admin:userUpdated', (data) {
      if (data != null && data is Map<String, dynamic>) {
        callback(UserModel.fromJson(data));
      }
    });
  }

  // Listen for group updates (optional real-time functionality)
  void listenForGroupUpdates(Function(GroupModel) callback) {
    _webSocketService.listen('admin:groupUpdated', (data) {
      if (data != null && data is Map<String, dynamic>) {
        callback(GroupModel.fromJson(data));
      }
    });
  }

  // Remove event listeners when done
  void dispose() {
    _webSocketService.off('admin:userUpdated');
    _webSocketService.off('admin:groupUpdated');
    // Don't disconnect the socket here as it might be used by other services
  }
}
