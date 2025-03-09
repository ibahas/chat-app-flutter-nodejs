// auth_service.dart
import 'dart:convert';
import 'package:chat_app/core/var.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/websocket_service.dart';

class AuthService {
  final WebSocketService _socketService = WebSocketService();

  // Keys for SharedPreferences
  static const String user_data_key = 'user_data';
  static const String auth_status_key = 'auth_status';

  // Sign in with email and password
  Future<UserModel?> signIn(String email, String password) async {
    try {
      final response = await _socketService.emitWithAck('login', {
        'email': email,
        'password': password,
      });

      if (response['success'] == true) {
        final token = response['token'];
        varToken = token;

        // // print("Login success, saving token: $token");
        // Store token in WebSocketService
        await _socketService.setAuthToken(token);

        // // print('User data before parsing:');
        // // print(response['user']);
        // // print('-------------------------------------');
        // Create user model from response
        final user = UserModel.fromJson(response['user']);

        // Save user data to local storage for persistence
        await _saveUserLocally(user);

        return user;
      }
      return null;
    } catch (e) {
      // print('Login error: $e');
      throw Exception('Login failed: $e');
    }
  }

  // Sign up with email and password
  Future<UserModel?> signUp(String email, String password, String name,
      {UserRole role = UserRole.user}) async {
    try {
      final response = await _socketService.emitWithAck('register', {
        'email': email,
        'password': password,
        'name': name,
        'role': role.toString().split('.').last,
      });

      if (response['success'] == true) {
        final token = response['token'];
        // Store token
        await _socketService.setAuthToken(token);

        // Create user model from response
        final user = UserModel.fromJson(response['user']);

        // Save user data to local storage for persistence
        await _saveUserLocally(user);

        return user;
      }
      return null;
    } catch (e) {
      // print('Signup error: $e');
      return null;
    }
  }

  // Sign out - clear both server and local session
  Future<void> signOut() async {
    try {
      await _socketService.emitWithAck('logout', {});
      await _socketService.clearAuthToken();

      // Clear locally stored user data
      await _clearUserData();
    } catch (e) {
      // print('Signout error: $e');
      // Even if server logout fails, still clear local data
      await _clearUserData();
    }
  }

  // Check if user is an admin
  Future<bool> isAdmin(String userId) async {
    try {
      final response = await _socketService.emitWithAck('checkAdminStatus', {
        'userId': userId,
      });

      return response['success'] == true && response['isAdmin'] == true;
    } catch (e) {
      // print('Admin check error: $e');
      return false;
    }
  }

  // Get current user info from server
  Future<UserModel?> getUserInfo() async {
    try {
      final response = await _socketService.emitWithAck('getUserInfo', {});

      if (response['success'] == true) {
        final user = UserModel.fromJson(response['user']);
        //Need to decode user and check blocked and if == 1 logout user.
        if (user.isBlocked) {
          await signOut();
          return null;
        }

        // Update local storage with fresh data
        await _saveUserLocally(user);

        return user;
      }
      return null;
    } catch (e) {
      // print('Get user info error: $e');
      return null;
    }
  }

  // Try to restore user session from local storage
  Future<UserModel?> tryAutoLogin() async {
    try {
      // First check if we have a stored user
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString(user_data_key);
      final isAuthenticated = prefs.getBool(auth_status_key) ?? false;

      if (!isAuthenticated || userData == null) {
        return null;
      }

      // Parse the stored user data
      final user = UserModel.fromJson(json.decode(userData));

      // Validate session with server
      try {
        // This will use the stored token to validate the session
        final validatedUser = await getUserInfo();
        if (validatedUser != null) {
          // Session is valid, return the fresh user data
          return validatedUser;
        } else {
          // Session is invalid, clear stored data
          await _clearUserData();
          return null;
        }
      } catch (e) {
        // print('Session validation error: $e');
        // If server validation fails but we have local data, return it
        // This allows offline login when server is unreachable
        return user;
      }
    } catch (e) {
      // print('Auto login error: $e');
      return null;
    }
  }

  // Save user data to local storage
  Future<void> _saveUserLocally(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(user_data_key, json.encode(user.toJson()));
      await prefs.setBool(auth_status_key, true);
    } catch (e) {
      // print('Save user data error: $e');
    }
  }

  // Clear all user data from local storage
  Future<void> _clearUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(user_data_key);
      await prefs.setBool(auth_status_key, false);
    } catch (e) {
      // print('Clear user data error: $e');
    }
  }
}
