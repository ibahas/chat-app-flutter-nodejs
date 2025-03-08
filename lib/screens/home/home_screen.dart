import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/providers/admin_provider.dart'; // Keep import for isAdmin check if needed
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../auth/login_screen.dart';
import '../chat/group_chat_screen.dart';
import '../admin/admin_control_panel.dart';

class HomeScreen extends StatefulWidget {
  final bool isAdmin;

  const HomeScreen({super.key, required this.isAdmin});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  Future<void> _initializeChat() async {
    try {
      if (mounted) {
        setState(() {
          _isInitializing = true;
        });
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      await chatProvider.initialize();

      if (authProvider.currentUser != null) {
        // Fetch user groups if they're not already loaded
        if (chatProvider.userGroups.isEmpty) {
          await _fetchUserGroups(authProvider.currentUser!.id);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error initializing chat: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _fetchUserGroups(String userId) async {
    // Separate method for fetching groups, so you can call if you need reload
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    try {
      await chatProvider.fetchUserGroups(userId);
    } catch (e) {
      print('Error fetching user groups: $e');
      // Handle error: show snackbar, retry etc. - You can enhance error handling here if needed
    }
  }

  void _showCreateGroupDialog() {
    final groupNameController = TextEditingController();
    final memberController = TextEditingController();
    List<String> selectedMemberIds = [];
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            List<UserModel> searchResults = []; // Initialize as empty list

            if (searchQuery.isNotEmpty) {
              searchResults = Provider.of<AdminProvider>(context, listen: false)
                  .users // Access users from AdminProvider
                  .where((user) =>
                      user.name
                          .toLowerCase()
                          .contains(searchQuery.toLowerCase()) &&
                      user.id !=
                          Provider.of<AuthProvider>(context, listen: false)
                              .currentUser!
                              .id)
                  .toList();
            } else {
              // Optionally show some default users or leave empty initially
              searchResults = []; // Or show some suggested users if you want
            }

            return AlertDialog(
              title: const Text('Create New Group'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: groupNameController,
                      decoration:
                          const InputDecoration(labelText: 'Group Name'),
                    ),
                    TextField(
                      controller: memberController,
                      decoration: const InputDecoration(
                        labelText: 'Search Users',
                      ),
                      onChanged: (text) {
                        setState(() {
                          searchQuery = text;
                          // Trigger user search here if needed, or let it happen on build
                        });
                      },
                    ),
                    SizedBox(
                      height: 150,
                      width: double.maxFinite,
                      child: ListView.builder(
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final user = searchResults[index];
                          final isSelected =
                              selectedMemberIds.contains(user.id);
                          return CheckboxListTile(
                            title: Text(user.name),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  selectedMemberIds.add(user.id);
                                } else {
                                  selectedMemberIds.remove(user.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    Wrap(
                      children: selectedMemberIds.map((memberId) {
                        final adminProvider =
                            Provider.of<AdminProvider>(context, listen: false);
                        final user = adminProvider.users.firstWhere((element) =>
                            element.id ==
                            memberId); // Get user from AdminProvider users
                        return Chip(
                          label: Text(user.name),
                          onDeleted: () {
                            setState(() {
                              selectedMemberIds.remove(memberId);
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);
                    final chatProvider =
                        Provider.of<ChatProvider>(context, listen: false);

                    if (groupNameController.text.isNotEmpty) {
                      await chatProvider.createGroup(
                        name: groupNameController.text,
                        adminId: authProvider.currentUser!.id,
                        memberIds: selectedMemberIds,
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secure Group Chat'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdminControlPanel()));
              },
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).logout();
              Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
            },
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                if (chatProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (chatProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: ${chatProvider.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            chatProvider.clearError();
                            _initializeChat();
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (chatProvider.userGroups.isEmpty) {
                  return const Center(
                    child: Text('No groups found. Create a new group!'),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);
                    await _fetchUserGroups(authProvider.currentUser!.id);
                  },
                  child: ListView.builder(
                    itemCount: chatProvider.userGroups.length,
                    itemBuilder: (context, index) {
                      final group = chatProvider.userGroups[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(group.name.substring(0, 1).toUpperCase()),
                        ),
                        title: Text(group.name),
                        subtitle: Text('${group.memberIds.length} members'),
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GroupChatScreen(
                              group: group,
                            ),
                          ));
                        },
                      );
                    },
                  ),
                );
              },
            ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: _showCreateGroupDialog,
              tooltip: 'Create New Group',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  @override
  void dispose() {
    // Clean up any resources
    super.dispose();
  }
}
