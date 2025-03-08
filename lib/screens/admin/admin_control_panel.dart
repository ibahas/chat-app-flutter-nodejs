import 'package:chat_app/providers/admin_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';

class AdminControlPanel extends StatefulWidget {
  const AdminControlPanel({super.key});
  @override
  _AdminControlPanelState createState() => _AdminControlPanelState();
}

class _AdminControlPanelState extends State<AdminControlPanel> {
  @override
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Fetch users and groups when the screen initializes
    final adminProvider = Provider.of<AdminProvider>(context, listen: false);
    adminProvider.fetchAllUsers();
    adminProvider.fetchAllGroups();
  }

  void _showUserDetailsDialog(UserModel user) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('User Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Name: ${user.name}'),
              Text('Email: ${user.email}'),
              Text('Role: ${user.role == UserRole.admin ? 'Admin' : 'User'}'),
              Text('Status: ${user.isBlocked ? 'Blocked' : 'Active'}'),
            ],
          ),
          actions: [
            if (!user.isBlocked)
              TextButton(
                onPressed: () {
                  Provider.of<AdminProvider>(context, listen: false)
                      .blockUser(user.id);
                  Navigator.of(context).pop();
                },
                child: const Text('Block User'),
              ),
            if (user.isBlocked)
              TextButton(
                onPressed: () {
                  Provider.of<AdminProvider>(context, listen: false)
                      .unblockUser(user.id);
                  Navigator.of(context).pop();
                },
                child: const Text('Unblock User'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Control Panel'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Users', icon: Icon(Icons.people)),
              Tab(text: 'Groups', icon: Icon(Icons.group_work)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Users Tab
            Consumer<AdminProvider>(
              builder: (context, adminProvider, child) {
                if (adminProvider.users.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  itemCount: adminProvider.users.length,
                  itemBuilder: (context, index) {
                    final user = adminProvider.users[index];
                    return ListTile(
                      title: Text(user.name),
                      subtitle: Text(user.email),
                      trailing: Icon(
                        user.isBlocked ? Icons.block : Icons.check_circle,
                        color: user.isBlocked ? Colors.red : Colors.green,
                      ),
                      onTap: () => _showUserDetailsDialog(user),
                    );
                  },
                );
              },
            ),

            // Groups Tab
            Consumer<AdminProvider>(
              builder: (context, adminProvider, child) {
                if (adminProvider.groups.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  itemCount: adminProvider.groups.length,
                  itemBuilder: (context, index) {
                    final group = adminProvider.groups[index];
                    return ListTile(
                      title: Text(group.name),
                      subtitle: Text('${group.memberIds.length} members'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Group'),
                              content: const Text(
                                  'Are you sure you want to delete this group?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    Provider.of<AdminProvider>(context,
                                            listen: false)
                                        .deleteGroup(group.id);
                                    Navigator.of(context).pop();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
