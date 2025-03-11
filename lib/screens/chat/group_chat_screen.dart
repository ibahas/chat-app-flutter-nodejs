import 'dart:async';
import 'package:chat_app/providers/admin_provider.dart';
import 'package:chat_app/providers/chat_provider.dart';
import 'package:chat_app/screens/chat/group_management_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/group_model.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/chat_service.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;

  const GroupChatScreen({super.key, required this.group});

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();
  late StreamSubscription<List<MessageModel>> _messageSubscription;
  final List<MessageModel> _messages = [];
  List<UserModel> _allUsers = [];
  late GroupModel groupModel;
  bool _allUsersLoaded = false;
  StreamSubscription<String>?
      _navigationSubscription; // Subscription for navigation stream

  @override
  void initState() {
    super.initState();
    groupModel = widget.group;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllUsers();
      _subscribeToMessages();
      _subscribeToNavigationEvents(); // Subscribe to navigation events
    });
    // check if current user id  exits in memberIds.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!widget.group.memberIds.contains(authProvider.currentUser!.id)) {
      //Route to home screen.
      Navigator.of(context).pop();
    }
  }

  void _subscribeToNavigationEvents() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _navigationSubscription = chatProvider.navigationStream.listen((groupId) {
      if (groupId == widget.group.id) {
        // User was removed from *this* group, navigate back to HomeScreen
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageSubscription.cancel();
    _navigationSubscription?.cancel(); // Cancel navigation subscription
    super.dispose();
  }

  // Load all users (for displaying names)
  Future<void> _loadAllUsers() async {
    if (_allUsersLoaded) return; // Prevent repeated calls
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    try {
      await chatProvider.fetchAllUsers();
      setState(() {
        _allUsers = chatProvider.users;
        _allUsersLoaded = true;
      });
    } catch (e) {
      print("Error loading all users: $e");
      // Handle the error, maybe show a snackbar
    }
  }

  // Subscribe to group messages
  void _subscribeToMessages() {
    _messageSubscription =
        _chatService.getGroupMessages(widget.group.id).listen(
      (List<MessageModel> newMessages) {
        if (mounted) {
          setState(() {
            // Avoid duplicates
            for (var msg in newMessages) {
              if (!_messages.any((existing) => existing.id == msg.id)) {
                _messages.insert(0, msg);
              }
            }
          });
        }
      },
      onError: (error) {
        debugPrint("Error receiving messages: $error");
      },
    );
  }

  // Send message
  void _sendMessage() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final senderId = authProvider.currentUser!.id;
    final content = _messageController.text.trim();

    if (content.isEmpty) return;

    final message = MessageModel(
      senderId: senderId,
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.text,
    );

    try {
      await _chatService.sendGroupMessage(
          groupId: widget.group.id, message: message);
      _messageController.clear();
    } catch (e) {
      debugPrint("Failed to send message: $e");
      // Optionally, remove the message if sending failed
    }
  }

  // Get sender name
  String _getUserName(String senderId) {
    print(_allUsers);
    print('getUserName: $senderId');

    try {
      return _allUsers.firstWhere((user) => user.id == senderId).name ??
          'Unknown User';
    } catch (e) {
      return 'Unknown User';
    }
  }

  // Build message item
  Widget _buildMessageItem(MessageModel message) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isCurrentUser = message.senderId == authProvider.currentUser!.id;

    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isCurrentUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isCurrentUser ? 'You' : _getUserName(message.senderId),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(message.content),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isAdmin = widget.group.adminId == authProvider.currentUser!.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(groupModel.name),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showGroupManagementDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageItem(_messages[index]);
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  void _showGroupManagementDialog() async {
    //Upgrade allUsers to a required parameter
    await _loadAllUsers();

    showDialog(
        context: context,
        builder: (context) {
          return GroupManagementDialog(
            groupId: widget.group.id,
            adminId: widget.group.adminId,
            memberIds: widget.group.memberIds,
            allUsers: _allUsers,
            groupModel: groupModel,
            onGroupUpdated: (GroupModel newGroup, List<String> newMemberIds) {
              // Handle newMemberIds
              setState(() {
                groupModel = newGroup;
                // UPDATE MEMBERIDS HERE TO NEW MEMBER IDS!
                widget.group.memberIds.clear();
                widget.group.memberIds.addAll(newMemberIds);
              });
            },
          );
        });
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
