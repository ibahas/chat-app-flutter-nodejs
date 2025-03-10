import 'dart:async';

import 'package:chat_app/models/group_model.dart';
import 'package:chat_app/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chat_app/models/user_model.dart';
import 'package:chat_app/providers/auth_provider.dart';
import 'package:chat_app/providers/chat_provider.dart';
import 'package:chat_app/providers/admin_provider.dart';
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
  final ChatService _chatService = ChatService();
  //Use the state in here to reload in all state
  late StreamSubscription<GroupModel> newgroupControllerGroup;
  //Use the state in here to reload in all state
  late StreamSubscription<GroupModel> removedUserFromUpdateGroup;

  List<UserModel> searchResults = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      //_subscribeToNewGroupJoined, _subscribeToRemoveUserFromGroup. with listenForNewGroupJoined,  listenForgroupToWasRemoved.
      newgroupControllerGroup = _chatService.listenForNewGroupJoined().listen(
        (group) {
          if (group.id.isNotEmpty) {
            //Add the group to the list of groups.
            // Provider.of<ChatProvider>(context, listen: false)
            //     .addUserGroup(group);
          }
        },
      );

      removedUserFromUpdateGroup =
          _chatService.listenForgroupToWasRemoved().listen(
        (group) {
          if (group.id.isNotEmpty) {
            //Remove the group from the list of groups.
            // Provider.of<ChatProvider>(context, listen: false)
            //     .removeUserGroup(group);
          }
        },
      );
    });
  }

  Future<void> _initializeChat() async {
    try {
      setState(() => _isInitializing = true);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      if (widget.isAdmin) {
        //Upgrade fetchUsers to get all users
        final adminProvider =
            Provider.of<AdminProvider>(context, listen: false);
        if (adminProvider.users.isEmpty) {
          await adminProvider.fetchAllUsers();
          searchResults = adminProvider.users;
        }
      }

      await chatProvider.initialize();
      if (authProvider.currentUser != null && chatProvider.userGroups.isEmpty) {
        await _fetchUserGroups(authProvider.currentUser!.id);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error initializing chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _fetchUserGroups(String userId) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    try {
      await chatProvider.fetchUserGroups(userId);
    } catch (e) {
      // print('Error fetching user groups: $e');
    }
  }

  //Steam to updates to current user if added to new group need to give him notification, and also to update the group list.
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => HomeScreen(isAdmin: widget.isAdmin)),
        );
        return false; // Prevent default back action
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Secure Group Chat'),
          actions: [
            if (widget.isAdmin)
              IconButton(
                icon: const Icon(Icons.admin_panel_settings),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AdminControlPanel()),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () {
                Provider.of<AuthProvider>(context, listen: false).logout();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
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
                            child:
                                Text(group.name.substring(0, 1).toUpperCase()),
                          ),
                          title: Text(group.name),
                          subtitle: Text('${group.memberIds.length} members'),
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => GroupChatScreen(group: group),
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
      ),
    );
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
            if (searchQuery.isNotEmpty) {
              searchResults = Provider.of<AdminProvider>(context, listen: false)
                  .users
                  .where((user) =>
                      user.name
                          .toLowerCase()
                          .contains(searchQuery.toLowerCase()) &&
                      user.id !=
                          Provider.of<AuthProvider>(context, listen: false)
                              .currentUser!
                              .id)
                  .toList();
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
                      decoration:
                          const InputDecoration(labelText: 'Search Users'),
                      onChanged: (text) {
                        setState(() {
                          searchQuery = text;
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
                        final user = adminProvider.users
                            .firstWhere((element) => element.id == memberId);
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
                      var res = await chatProvider.createGroup(
                        name: groupNameController.text,
                        adminId: authProvider.currentUser!.id,
                        memberIds: selectedMemberIds,
                      );
                      // if 'success' => false . need to logout .
                      if (res['success'] == false) {
                        await Provider.of<AuthProvider>(context, listen: false)
                            .logout();

                        await Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                        );
                        return;
                      }
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
}
