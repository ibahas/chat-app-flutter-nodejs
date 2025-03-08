import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  static const String AUTH_TOKEN_KEY = 'auth_token';

  late io.Socket _socket;
  final String _serverUrl =
      'http://localhost:3000'; // Change to your server URL
  bool _isConnected = false;
  bool _isInitialized = false;
  Map<String, dynamic> _socketOptions = {};

  Future<void> initialize() async {
    if (_isInitialized) return;

    final token = await getAuthToken();
    print("WebSocketService init, found token: $token");

    _socketOptions = {
      'transports': ['websocket'],
      'autoConnect': true,
      'auth': {'token': token}
    };

    _socket = io.io(_serverUrl, _socketOptions);

    _setupSocketListeners();
    _isInitialized = true;
  }

  void _setupSocketListeners() {
    _socket.onConnect((_) {
      print('Connected to WebSocket server');
      _isConnected = true;
    });

    _socket.onDisconnect((_) {
      print('Disconnected from WebSocket server');
      _isConnected = false;
    });

    _socket.onError((error) {
      print('WebSocket Error: $error');
    });

    _socket.onConnectError((error) {
      print('Connection Error: $error');
    });
  }

  Future<Map<String, dynamic>> emitWithAck(
      String event, Map<String, dynamic> data) async {
    if (!_isInitialized) {
      await initialize();
    }

    Completer<Map<String, dynamic>> completer = Completer();

    if (!_isConnected) {
      await _reconnect();
    }

    _socket.emitWithAck(event, data, ack: (response) {
      if (response is Map<String, dynamic>) {
        completer.complete(response);
      } else {
        // Handle unexpected response format
        completer
            .complete({'success': false, 'message': 'Invalid response format'});
      }
    });

    // Add timeout
    return completer.future.timeout(const Duration(seconds: 10),
        onTimeout: () => {'success': false, 'message': 'Request timed out'});
  }

  Future<void> _reconnect() async {
    Completer<void> completer = Completer();

    if (!_socket.connected) {
      _socket.connect();
      _socket.onConnect((data) {
        _isConnected = true;
        if (!completer.isCompleted) completer.complete();
      });
    } else {
      _isConnected = true;
      completer.complete();
    }

    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      throw Exception('Connection timeout');
    });
  }

  void emit(String event, Map<String, dynamic> data) {
    if (_isConnected) {
      _socket.emit(event, data);
    } else {
      print('Socket not connected. Cannot emit event: $event');
    }
  }

  void listen(String event, Function(dynamic) callback) {
    _socket.on(event, callback);
  }

  void off(String event) {
    _socket.off(event);
  }

  void disconnect() {
    _socket.disconnect();
  }

  // Token management methods
  Future<void> setAuthToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AUTH_TOKEN_KEY, token);

    // Update socket auth in our local options
    _socketOptions['auth'] = {'token': token};

    // Reconnect to apply changes
    if (_isConnected) {
      _socket.disconnect();
      // Create a new socket with updated options
      _socket = io.io(_serverUrl, _socketOptions);
      _setupSocketListeners();
      _socket.connect();
    }
  }

  Future<String?> getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AUTH_TOKEN_KEY);
  }

  Future<void> clearAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AUTH_TOKEN_KEY);

    // Update socket auth in our local options
    _socketOptions['auth'] = {'token': null};

    // Reconnect to apply changes
    if (_isConnected) {
      _socket.disconnect();
      // Create a new socket with updated options
      _socket = io.io(_serverUrl, _socketOptions);
      _setupSocketListeners();
      _socket.connect();
    }
  }
}
