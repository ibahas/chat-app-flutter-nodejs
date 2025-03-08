import 'package:flutter/material.dart';

class UserChatsScreen extends StatelessWidget {
  const UserChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Chats'),
      ),
      body: const Center(
        child: Text('List of user chats will be displayed here.'),
      ),
    );
  }
}