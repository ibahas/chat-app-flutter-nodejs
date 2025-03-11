import 'dart:async';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/services/chat_service.dart';
import 'package:flutter/material.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../services/websocket_service.dart';

class ChatProvider with ChangeNotifier {
  final ChatService _chatService = ChatService();

  final WebSocketService _socketService = WebSocketService();

  final StreamController<String> _navigationController =
      StreamController<String>.broadcast(); // Stream for navigation events
  Stream<String> get navigationStream =>
      _navigationController.stream; // Expose the stream

  final StreamController<GroupModel> _groupController =
      StreamController<GroupModel>.broadcast();

  List<GroupModel> _userGroups = [];
  List<UserModel> users = [];
  final List<MessageModel> _currentGroupMessages = [];
  bool _isLoading = false;
  String? _error;
  final StreamController<List<MessageModel>> _messageController =
      StreamController<List<MessageModel>>.broadcast();
  //We don't use this line for that new logic to do correct reload.

  //Stream for list of groups
  final StreamController<GroupModel> _newGroupController =
      StreamController<GroupModel>.broadcast();
  final StreamController<GroupModel> _removeUserFrom =
      StreamController<GroupModel>.broadcast();

  List<GroupModel> get userGroups => _userGroups;
  List<MessageModel> get currentGroupMessages => _currentGroupMessages;
  bool get isLoading => _isLoading;
  String? get error => _error;

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

  ChatProvider() {
    initialize();

    _socketService.listen('newGroupJoined', _handleNewGroup);
    _socketService.listen('updateOfGroupName', _handleUpdateGroupName);
    // _socketService.listen('removeUserFrom', removeUserFrom);
    _socketService.listen('admin:deleteGroup',
        _handleAdminDeleteGroup); // ADDED: listen admin:deleteGroup
    _socketService.listen('admin:groupUpdated',
        _handleAdminDeleteGroup); // ADDED: listen admin:groupUpdated

    _socketService.listen('removedFromGroup',
        _handleRemovedFromGroup); // Listen for the new event

    //getAllUsers.
    fetchAllUsers();
  }

  void _handleRemovedFromGroup(dynamic data) {
    if (data != null &&
        data is Map<String, dynamic> &&
        data.containsKey('groupId')) {
      String groupId = data['groupId'];
      _navigationController
          .add(groupId); // Add the groupId to the navigation stream
      // Optionally, update _userGroups to remove the group locally
      _userGroups.removeWhere((group) => group.id == groupId);
      notifyListeners(); // Notify listeners about group list change
    }
  }

  @override
  void dispose() {
    _messageController.close();
    _newGroupController.close();
    _removeUserFrom.close();
    _navigationController.close(); // Close the stream controller

    super.dispose();
  }

  //Remove User function.
  void removeUserFrom(data) {
    if (data != null) {
      // print('remove: ${data['userID']}');
      _removeUserFrom.add(GroupModel.fromJson(data));
    } else {
      print('removeUser is null');
    }
  }

  _handleUpdateGroupName(data) async {
    if (data != null) {
      GroupModel updateModel = GroupModel.fromJson(data);
      _groupController.add(updateModel); // Send the new model
      //For update group name in userGroups.
      final index =
          _userGroups.indexWhere((element) => element.id == updateModel.id);
      if (index != -1) {
        _userGroups[index] = updateModel;
        notifyListeners();
      }
    } else {
      print('Admin updateGroupName Error data it null or not found');
    }
  }

  //Handle group to was removed.
  void _handleGroupToWasRemoved(data) async {
    if (data != null) {
      //Remove from _userGroups.
      GroupModel gr = GroupModel.fromJson(data);
      _userGroups.removeWhere((element) => element.id == gr.id);
      notifyListeners();
    }
  }

  //Handle new group
  void _handleNewGroup(data) async {
    print(_userGroups);
    //Check if group exist.
    GroupModel newGroup = GroupModel.fromJson(data);
    //Check the ip of newGroup exist in userGroups without any.
    //Using addWhere.
    if (!_userGroups.any((element) => element.id == newGroup.id)) {
      //Add the new group to userGroups.
      _userGroups.add(newGroup);
      notifyListeners();
    }

    notifyListeners();
  }

  Future<void> refreshUserGroups(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();
      //webScoket calls
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
      // listenForNewGroup(userId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  void listenForNewGroup(String userId) {
    _socketService.listen('newGroupJoined', (data) async {
      if (data != null) {
        GroupModel newGroup = GroupModel.fromJson(data);
        List<String> members = newGroup.memberIds.cast<String>().toList();

        if (!members.contains(userId)) {
          members.add(userId);
          // Make sure the local UserModel also has this group in the List
          _userGroups.add(newGroup);
          notifyListeners();
        }
      }
    });
  }

  //Create group messages stream
  Stream<List<MessageModel>> groupMessagesStream(String groupId) {
    return _messageController.stream;
  }

  Future<bool> updateGroup(String groupId, Map<String, dynamic> updates) async {
    try {
      final response = await _socketService.emitWithAck('updateGroup', {
        'groupId': groupId,
        ...updates,
      });

      if (response['success'] == true) {
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to update group');
      }
    } catch (e) {
      print('Error updating group: $e');
      return false;
    }
  }

  void onGroupMessageReceived(
      String groupId, Function(List<MessageModel>) onMessageReceived) {
    _socketService.listen('groupMessages:$groupId', (data) {
      if (data is List) {
        final messages = data.map((msg) => MessageModel.fromJson(msg)).toList();
        _messageController.add(messages); // Add messages to the stream
        onMessageReceived(messages);
      } else {
        print(
            'ChatProvider - onGroupMessageReceived - Unexpected data format: $data');
      }
    });
  }

  void listenToGroupMessages(String groupId) {
    _socketService.emit('joinGroup', {'groupId': groupId});
  }

  Future<void> fetchUserGroups(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();
//webScoket calls
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

// Listen for new groups
      _socketService.listen('newGroupJoined', _handleNewGroup);
      //listen for new group.
      _socketService.listen('groupToWasRemoved', _handleGroupToWasRemoved);
      // Listen for updates to group names
      _socketService.listen('updateOfGroupName', _handleUpdateGroupName);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  // Create a new group
  Future<Map<String, dynamic>> createGroup({
    required String name,
    required String adminId,
    required List<String> memberIds,
  }) async {
    final response = await _socketService.emitWithAck('createGroup', {
      'name': name,
      // 'adminId': adminId,
      'members': memberIds,
    });

    if (!response['success']) {
      //Snak.
      SnackBar(content: Text(response['message'] ?? 'Failed to create group'));
    }
    return response;
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

  void _handleAdminDeleteGroup(dynamic data) async {
    if (data != null &&
        data is Map<String, dynamic> &&
        data.containsKey('id')) {
      String groupIdToDelete = data['id'];
      print(groupIdToDelete);

      _userGroups.removeWhere((group) => group.id == groupIdToDelete);
      notifyListeners(); // Notify that the list has changed
      print('Group with ID: $groupIdToDelete has been deleted.');
    } else {
      print('Admin deleteGroup Error data it null or not found');
    }
  }

  //_handleGroupName
  // void _handleGroupName(dynamic data) async {
  //   if (data != null &&
  //       data is Map<String, dynamic> &&
  //       data.containsKey('id')) {
  //     String groupIdToDelete = data['id'];
  //     print(groupIdToDelete);

  //     _userGroups.removeWhere((group) => group.id == groupIdToDelete);
  //     notifyListeners(); // Notify that the list has changed
  //     print('Group with ID: $groupIdToDelete has been deleted.');
  //   } else {
  //     print('Admin deleteGroup Error data it null or not found');
  //   }
  // }

  void notifyRebuild() {
    super.notifyListeners();
  }

  //addUserGroup
  void addUserGroup(GroupModel group) {
    _userGroups.add(group);
    notifyListeners();
  }

  //removeUserGroup.
  void removeUserGroup(GroupModel group) {
    final index = _userGroups.indexWhere((element) => element.id == group.id);
    if (index != -1) {
      _userGroups.removeAt(index);
    }

    notifyListeners();
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
        // throw Exception(response['message'] ?? 'Failed to update group');
        SnackBar(
            content: Text(response['message'] ?? 'Failed to update group'));
        return false;
      }
    } catch (e) {
// print('Error updating group: $e');
      return false;
    }
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
        // throw Exception(
        //     response['message'] ?? 'Failed to remove user from group');
        SnackBar(
            content: Text(
          response['message'] ?? 'Failed to remove user from group',
        ));
        return false;
      }
    } catch (e) {
      // print('Error removing user from group: $e');
      return false; // Return false for failure
    }
  }

  //Add user from group
  Future<bool> addUserToGroup(String groupId, String userId) async {
    try {
      final response = await _socketService.emitWithAck('addUserToGroup', {
        'groupId': groupId,
        'userId': userId,
      });
      // print('addUserToGroup response $response');
      if (response['success'] == true) {
        //Update current Group memberIds.
        for (var element in _userGroups) {
          if (element.id == groupId) {
            element.memberIds.add(userId);
          }
        }
        notifyListeners();
        return true; // Return true for success
      } else {
        // throw Exception(response['message'] ?? 'Failed to add user to group');
        SnackBar(
            content: Text(
          response['message'] ?? 'Failed to add user to group',
        ));
        return false;
      }
    } catch (e) {
      // print('Error adding user to group: $e');
      return false; // Return false for failure
    }
  }

  //fetchAllUsers
  Future<void> fetchAllUsers() async {
    try {
      users = await _chatService.getAllUsers();
      notifyListeners();
    } catch (e) {
      // // print('Error fetching users: $e');
    }
  }
}

void addUsersListener(String users) async {
  final String memberId = users;
  print(
      'Group name is: ===========================================================================$users');
}
