import 'package:flutter/material.dart';
import 'dart:convert'; // For JSON encoding/decoding
import 'package:web_socket_channel/web_socket_channel.dart';

// --- Data Models ---

class User {
  final String id;
  final String username;
  final String password;  // Store securely on the server (hashed)!
  final String role;

  User({required this.id, required this.username, required this.password, required this.role});

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      password: json['password'],
      role: json['role'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password': password,
        'role': role,
      };
}

class Group {
  final String id;
  final String name;
  final String password;
  final List<String> users;

  Group({required this.id, required this.name, required this.password, required this.users});

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      password: json['password'],
      users: List<String>.from(json['users']),
    );
  }
}

class Message {
  final String senderId;
  final String groupId;
  final String content;
  final DateTime timestamp;

  Message({required this.senderId, required this.groupId, required this.content, required this.timestamp});

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      senderId: json['senderId'],
      groupId: json['groupId'],
      content: json['content'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}


// --- WebSocket Service ---

class WebSocketService {
  final String serverUrl;
  late WebSocketChannel _channel;
  Function(dynamic)? onMessageReceived;  // Callback for handling messages

  WebSocketService({required this.serverUrl, this.onMessageReceived});

  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(serverUrl));

    _channel.stream.listen((message) {
      if (onMessageReceived != null) {
        onMessageReceived!(message);
      }
    }, onError: (error) {
      print("WebSocket error: $error");
    }, onDone: () {
      print("WebSocket connection closed");
    });
  }

  void sendMessage(Map<String, dynamic> data) {
    _channel.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _channel.sink.close();
  }
}


// --- Auth Service ---

class AuthService {
  User? currentUser;

  Future<bool> login(String username, String password) async {
    // Simulate login request over WebSocket (replace with actual request)
    // In a real app, you would send username/password to the server,
    // which would validate and return user data.
    // For this example, we hardcode a user for demonstration.
    if (username == "test" && password == "password") {
      currentUser = User(id: "123", username: username, password: password, role: 'user');
      return true;
    }
    if (username == "admin" && password == "password") {
      currentUser = User(id: "456", username: username, password: password, role: 'admin');
      return true;
    }
    return false;
  }

  void logout() {
    currentUser = null;
  }

  bool isLoggedIn() {
    return currentUser != null;
  }
}


// --- App State (Simple, without Provider) ---

class AppState {
  AuthService authService = AuthService();
  WebSocketService webSocketService = WebSocketService(serverUrl: 'ws://your-node-server:3000'); // Replace with your server URL
  List<Group> groups = [];
  User? selectedUser;

  AppState() {
    // Initialize WebSocket connection here or after login
  }

  void updateGroups(List<Group> newGroups) {
    groups = newGroups;
  }
}

// --- Screens ---

class LoginScreen extends StatefulWidget {
  final AppState appState;

  LoginScreen({Key? key, required this.appState}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _errorMessage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Login")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final username = _usernameController.text;
                final password = _passwordController.text;

                bool isLoggedIn = await widget.appState.authService.login(username, password);

                if (isLoggedIn) {
                  // Navigate to Home Screen
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomeScreen(appState: widget.appState),
                    ),
                  );
                } else {
                  setState(() {
                    _errorMessage = 'Invalid username or password';
                  });
                }
              },
              child: const Text("Login"),
            ),
            if (_errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10.0),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final AppState appState;

  const HomeScreen({Key? key, required this.appState}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  @override
  void initState() {
    super.initState();
    // Connect to websocket and set onMessageReceived callback
    widget.appState.webSocketService.connect();
    widget.appState.webSocketService.onMessageReceived = _handleWebSocketMessage;
    _fetchGroups();
  }

  @override
  void dispose() {
    widget.appState.webSocketService.disconnect();
    super.dispose();
  }

  void _fetchGroups() {
    // Simulate fetching groups from the server
    widget.appState.webSocketService.sendMessage({'type': 'get_groups'});
  }

  void _handleWebSocketMessage(dynamic message) {
    // Process the WebSocket message and update the state.
    final decodedMessage = jsonDecode(message);

    if (decodedMessage['type'] == 'groups_data') {
      List<dynamic> groupsJson = decodedMessage['groups'];
      List<Group> groups = groupsJson.map((groupJson) => Group.fromJson(groupJson)).toList();
      setState(() {
        widget.appState.updateGroups(groups); // Update app state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Home")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.appState.groups.length,
              itemBuilder: (context, index) {
                final group = widget.appState.groups[index];
                return ListTile(
                  title: Text(group.name),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => GroupChatScreen(appState: widget.appState, groupId: group.id),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // Logout
              widget.appState.authService.logout();
              widget.appState.webSocketService.disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => LoginScreen(appState: widget.appState),
                ),
              );
            },
            child: const Text("Logout"),
          ),
          if (widget.appState.authService.currentUser?.role == 'admin')
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminScreen(appState: widget.appState),
                  ),
                );
              },
              child: const Text("Admin Panel"),
            ),
        ],
      ),
    );
  }
}


class GroupChatScreen extends StatefulWidget {
  final AppState appState;
  final String groupId;

  const GroupChatScreen({Key? key, required this.appState, required this.groupId}) : super(key: key);

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _messageController = TextEditingController();
  List<Message> _messages = [];  // Messages for this group

  @override
  void initState() {
    super.initState();
    widget.appState.webSocketService.onMessageReceived = _handleWebSocketMessage;
  }

  void _handleWebSocketMessage(dynamic message) {
    final decodedMessage = jsonDecode(message);

    if (decodedMessage['type'] == 'new_message' && decodedMessage['groupId'] == widget.groupId) {
      Message newMessage = Message.fromJson(decodedMessage['message']);
      setState(() {
        _messages.add(newMessage);
      });
    }
  }

  void _sendMessage() {
    final messageText = _messageController.text;
    if (messageText.isNotEmpty) {
      final message = {
        'type': 'send_message',
        'groupId': widget.groupId,
        'senderId': widget.appState.authService.currentUser!.id,
        'content': messageText,
      };
      widget.appState.webSocketService.sendMessage(message);
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Chat")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ListTile(
                  title: Text(message.content),
                  subtitle: Text(message.senderId), // Display sender
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(hintText: "Enter message"),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminScreen extends StatelessWidget {
  final AppState appState;

  const AdminScreen({Key? key, required this.appState}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Panel")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserManagementScreen(appState: appState),
                  ),
                );
              },
              child: const Text("Manage Users"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupManagementScreen(appState: appState),
                  ),
                );
              },
              child: const Text("Manage Groups"),
            ),
          ],
        ),
      ),
    );
  }
}

class UserManagementScreen extends StatefulWidget {
  final AppState appState;

  const UserManagementScreen({Key? key, required this.appState}) : super(key: key);

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  void _fetchUsers() {
    // Simulate fetching users from the server
    widget.appState.webSocketService.sendMessage({'type': 'get_users'});
  }

  void _handleWebSocketMessage(dynamic message) {
    // Process the WebSocket message and update the state.
    final decodedMessage = jsonDecode(message);

    if (decodedMessage['type'] == 'users_data') {
      List<dynamic> usersJson = decodedMessage['users'];
      List<User> users = usersJson.map((userJson) => User.fromJson(userJson)).toList();
      setState(() {
        _users = users; // Update app state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Management")),
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          return ListTile(
            title: Text(user.username),
            subtitle: Text('Role: ${user.role}'),
            onTap: () {
              setState(() {
                widget.appState.selectedUser = user;
              });
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserDetailsScreen(appState: widget.appState, user: user),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to Add User Screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddUserScreen(appState: widget.appState),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class UserDetailsScreen extends StatelessWidget {
  final AppState appState;
  final User user;

  const UserDetailsScreen({Key? key, required this.appState, required this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Details")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Username: ${user.username}'),
            Text('Role: ${user.role}'),
            // Add more user details here
          ],
        ),
      ),
    );
  }
}

class AddUserScreen extends StatefulWidget {
  final AppState appState;

  const AddUserScreen({Key? key, required this.appState}) : super(key: key);

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _roleController = TextEditingController();

  void _addUser() {
    final username = _usernameController.text;
    final password = _passwordController.text;
    final role = _roleController.text;
    final newUser = {
      'type': 'add_user',
      'username': username,
      'password': password,
      'role': role,
    };
    widget.appState.webSocketService.sendMessage(newUser);

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add User")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(labelText: "Role"),
            ),
            ElevatedButton(
              onPressed: _addUser,
              child: const Text("Add User"),
            ),
          ],
        ),
      ),
    );
  }
}

class GroupManagementScreen extends StatefulWidget {
  final AppState appState;

  const GroupManagementScreen({Key? key, required this.appState}) : super(key: key);

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  List<Group> _groups = [];

  @override
  void initState() {
    super.initState();
    _fetchGroups();
  }

  void _fetchGroups() {
    // Simulate fetching groups from the server
    widget.appState.webSocketService.sendMessage({'type': 'get_groups'});
  }

  void _handleWebSocketMessage(dynamic message) {
    // Process the WebSocket message and update the state.
    final decodedMessage = jsonDecode(message);

    if (decodedMessage['type'] == 'groups_data') {
      List<dynamic> groupsJson = decodedMessage['groups'];
      List<Group> groups = groupsJson.map((groupJson) => Group.fromJson(groupJson)).toList();
      setState(() {
        _groups = groups; // Update app state
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Group Management")),
      body: ListView.builder(
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          return ListTile(
            title: Text(group.name),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GroupDetailsScreen(appState: widget.appState, group: group),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to Add Group Screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddGroupScreen(appState: widget.appState),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class GroupDetailsScreen extends StatefulWidget {
  final AppState appState;
  final Group group;

  const GroupDetailsScreen({Key? key, required this.appState, required this.group}) : super(key: key);

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  List<User> _users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  void _fetchUsers() {
    // Simulate fetching users from the server
    widget.appState.webSocketService.sendMessage({'type': 'get_users'});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Group Details")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Group Name: ${widget.group.name}'),
            Text('Password: ${widget.group.password}'),
            // Add more group details here
            const Text('Users:'),
            Expanded(
              child: ListView.builder(
                itemCount: widget.group.users.length,
                itemBuilder: (context, index) {
                  final userId = widget.group.users[index];
                  // Find the user in the list of users
                  return ListTile(
                    title: Text('User ID: $userId'),
                    // You can fetch user details based on userId if needed
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddGroupScreen extends StatefulWidget {
  final AppState appState;

  const AddGroupScreen({Key? key, required this.appState}) : super(key: key);

  @override
  State<AddGroupScreen> createState() => _AddGroupScreenState();
}

class _AddGroupScreenState extends State<AddGroupScreen> {
  final _groupNameController = TextEditingController();
  final _passwordController = TextEditingController();

  void _addGroup() {
    final groupName = _groupNameController.text;
    final password = _passwordController.text;
    final newGroup = {
      'type': 'add_group',
      'groupName': groupName,
      'password': password,
    };
    widget.appState.webSocketService.sendMessage(newGroup);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Group")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _groupNameController,
              decoration: const InputDecoration(labelText: "Group Name"),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            ElevatedButton(
              onPressed: _addGroup,
              child: const Text("Add Group"),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Main App ---

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({Key? key}) : super(key: key);

  final AppState appState = AppState();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Chat App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: LoginScreen(appState: appState), // Start with the Login Screen
    );
  }
}