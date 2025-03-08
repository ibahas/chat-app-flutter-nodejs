import 'dart:async';

import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/providers/admin_provider.dart';
import 'package:chat_app/providers/voice_provider.dart';
import 'package:chat_app/screens/chat/group_management_dialog';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/group_model.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;

  const GroupChatScreen({super.key, required this.group});

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final List<MessageModel> _messages = [];
  final _messageController = TextEditingController();
  List<UserModel> _allUsers = [];
  StreamSubscription<List<MessageModel>>? _messageSubscription;
  late GroupModel groupModel;

  @override
  void initState() {
    super.initState();
    groupModel = widget.group;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllUsers();
      _subscribeToMessages();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    try {
      final adminProvider = Provider.of<AdminProvider>(context, listen: false);
      await adminProvider.fetchAllUsers();
      if (mounted) {
        setState(() {
          _allUsers = adminProvider.users;
        });
      }
    } catch (e) {
      print("Error loading all users: $e");
    }
  }

  Future<void> _subscribeToMessages() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // 1. Start listening for new messages
    chatProvider.listenToGroupMessages(widget.group.id);

    // 2. Continue listening for new messages via the stream (your existing stream listener - now it's the *only* source of messages)
    _messageSubscription = chatProvider
        .groupMessagesStream(widget.group.id)
        .listen((List<MessageModel> newMessages) {
      print(
          'GroupChatScreen - Message stream update received - GroupId: ${widget.group.id}');
      if (mounted) {
        setState(() {
          _messages.insertAll(0, newMessages);
        });
      }
    });
  }

  void _sendMessage({MessageType type = MessageType.text}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final voiceProvider =
        Provider.of<VoiceMessageProvider>(context, listen: false);

    String content = type == MessageType.text
        ? _messageController.text.trim()
        : voiceProvider.uploadedVoiceUrl ?? '';

    if (content.isEmpty) return;

    // **Immediately add the message to the local list**
    final message = MessageModel(
      senderId: authProvider.currentUser!.id,
      content: content,
      timestamp: DateTime.now(),
      type: type,
    );
    setState(() {
      _messages.insert(0, message); // Insert at the beginning for reversed list
    });

    await chatProvider.sendGroupMessage(
      groupId: widget.group.id,
      senderId: authProvider.currentUser!.id,
      content: content,
      type: type,
    );
    _messageController
        .clear(); // **Uncomment this line to clear the input field**
  }

  Widget _buildMessageInput() {
    final voiceProvider = Provider.of<VoiceMessageProvider>(context);

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
            onPressed: () => _sendMessage(),
          ),
        ],
      ),
    );
  }

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
              isCurrentUser ? 'You:' : getUserName(message.senderId),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (message.type == MessageType.text) Text(message.content),
            if (message.type == MessageType.voice)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mic),
                  const Text('Voice Message'),
                  IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      Provider.of<VoiceMessageProvider>(context, listen: false)
                          .playVoiceMessage(message.content);
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String getUserName(String senderId) {
    try {
      final user = _allUsers.firstWhere((element) => element.id == senderId);
      return user.name;
    } catch (e) {
      return 'Unknown User';
    }
  }

  void _showGroupManagementDialog() {
    showDialog(
        context: context,
        builder: (context) {
          return GroupManagementDialog(
            groupModel: groupModel,
            groupId: widget.group.id,
            adminId: widget.group.adminId,
            memberIds: widget.group.memberIds,
            allUsers: _allUsers,
            onGroupUpdated: (GroupModel updatedGroup) {
              //widget.group = updatedGroup;
              groupModel = updatedGroup;
              setState(() {});
            },
          );
        });
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
                final message = _messages[index];
                return _buildMessageItem(message);
              },
            ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }
}
