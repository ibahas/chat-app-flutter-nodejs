// admin_provider.dart
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../services/admin_service.dart';

class AdminProvider with ChangeNotifier {
  final AdminService _adminService = AdminService();

  List<UserModel> _users = [];
  List<GroupModel> _groups = [];

  List<UserModel> get users => _users;
  List<GroupModel> get groups => _groups;

  AdminProvider() {
    fetchAllUsers();
  }

  Future<void> fetchAllUsers() async {
    try {
      _users = await _adminService.getAllUsers();
      notifyListeners();
    } catch (e) {
      // // print('Error fetching users: $e');
    }
  }

  Future<void> blockUser(String userId) async {
    try {
      await _adminService.blockUser(userId);
      await fetchAllUsers();
    } catch (e) {
      // // print('Error blocking user: $e');
    }
  }

  Future<void> unblockUser(String userId) async {
    try {
      await _adminService.unblockUser(userId);
      await fetchAllUsers();
    } catch (e) {
      // print('Error unblocking user: $e');
    }
  }

  Future<void> fetchAllGroups() async {
    try {
      _groups = await _adminService.getAllGroups();
      notifyListeners();
    } catch (e) {
      // print('Error fetching groups: $e');
    }
  }

  Future<void> deleteGroup(String groupId) async {
    try {
      await _adminService.deleteGroup(groupId);
      await fetchAllGroups();
    } catch (e) {
      // print('Error deleting group: $e');
    }
  }
}
