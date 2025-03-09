// auth_provider.dart
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  UserModel? _currentUser;
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isInitializing = true;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitializing => _isInitializing;

  // Constructor that tries auto-login
  AuthProvider() {
    _initializeAuthState();
  }

  // Initialize authentication state by trying auto-login
  Future _initializeAuthState() async {
    _isInitializing = true;
    notifyListeners();

    try {
      // Try to restore user session
      final user = await _authService.tryAutoLogin();
      if (user != null) {
        _currentUser = user;
      }
    } catch (e) {
      // print('Auth initialization error: $e');
    }

    _isInitializing = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = await _authService.signIn(email, password);

      _isLoading = false;

      if (user != null) {
        _currentUser = user;
        notifyListeners();
        return true;
      }

      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      // print('Login error in provider: $e');
      return false;
    }
  }

  Future<bool> signUp(String email, String password, String name,
      {UserRole role = UserRole.user}) async {
    try {
      _isLoading = true;
      notifyListeners();

      final user = await _authService.signUp(email, password, name, role: role);

      _isLoading = false;

      if (user != null) {
        _currentUser = user;
        notifyListeners();
        return true;
      }

      notifyListeners();
      return false;
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      // print('Signup error in provider: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      _isLoading = true;
      notifyListeners();

      await _authService.signOut();
      _currentUser = null;

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      // print('Logout error: $e');
    }
  }

  Future<bool> checkAdminStatus() async {
    if (_currentUser == null) return false;
    return await _authService.isAdmin(_currentUser!.id);
  }

  // Refresh user data from server
  Future<void> refreshUserData() async {
    if (_currentUser == null) return;

    try {
      final updatedUser = await _authService.getUserInfo();
      if (updatedUser != null) {
        _currentUser = updatedUser;
        notifyListeners();
      }
    } catch (e) {
      // print('Refresh user data error: $e');
    }
  }
}
