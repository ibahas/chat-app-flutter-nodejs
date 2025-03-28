import 'package:chat_app/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/group_model.dart';
import '../../providers/chat_provider.dart';
import '../../providers/auth_provider.dart'; //IMPORT AUTH PROVIDER.

class GroupManagementDialog extends StatefulWidget {
  final GroupModel groupModel;
  final String groupId;
  final String adminId;
  final List<String> memberIds;
  final List<UserModel> allUsers;
  final Function(GroupModel newGroup, List<String> newMemberIds)
      onGroupUpdated; // Modified callback

  const GroupManagementDialog({
    super.key,
    required this.groupModel,
    required this.groupId,
    required this.adminId,
    required this.memberIds,
    required this.allUsers,
    required this.onGroupUpdated,
  });

  @override
  State<GroupManagementDialog> createState() => _GroupManagementDialogState();
}

class _GroupManagementDialogState extends State<GroupManagementDialog> {
  late String groupName;
  List<String> groupMemberIds = [];

  @override
  void initState() {
    super.initState();
    groupName = widget.groupModel.name;
    groupMemberIds = List.from(widget.memberIds);
  }

  // Function to show group name edition dialog
  Future<void> _showEditGroupNameDialog(BuildContext context) async {
    final TextEditingController groupNameController = TextEditingController();
    groupNameController.text = groupName;

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Change Group Name'),
          content: TextField(
            controller: groupNameController,
            decoration: const InputDecoration(hintText: 'New group name'),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Save'),
              onPressed: () async {
                final newGroupName = groupNameController.text;

                final chatProvider =
                    Provider.of<ChatProvider>(context, listen: false);
                // Call WebSocket here for Update the group name
                bool isSuccess =
                    await _updateGroupName(widget.groupId, newGroupName);

                if (isSuccess) {
                  final newGroup =
                      widget.groupModel.copyWith(name: newGroupName);
                  widget.onGroupUpdated(
                      newGroup, groupMemberIds); // Pass memberIds too
                  setState(() {
                    groupName = newGroupName; // Update internal state of Dialog
                  });
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Method to handle the WebSocket send Group update
  Future<bool> _updateGroupName(String groupId, String newGroupName) async {
    // 1. Get the Provider
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    bool isSuccess = false;
    try {
      isSuccess = await chatProvider.updateGroupName(
          widget.groupId, {'name': newGroupName}); //Correct method name here
    } catch (error) {
      // print('error when update group: $error');
    }
    return isSuccess;
  }

  // This function to remove an user from the list
  void _showRemoveConfirmationDialog(BuildContext context, UserModel user) {
    //FINAL VARIBABLE THAT CHECK WHO IS ADMIN IF FALSE IS IMPOSSIBLE DO ACTION!//
    final bool isAdmin = widget.adminId ==
        context
            .read<AuthProvider>()
            .currentUser
            ?.id; //GET CORRECT CALL THE ADMIN
    //END

    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Only the admin can remove users!")));
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Removal'),
          content: Text(
              'Are you sure you want to remove ${user.name} from the group?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                //  call here webSocket remove User
                final chatProvider =
                    Provider.of<ChatProvider>(context, listen: false);

                // Call here webSocket to remove User
                bool isRemoved = await chatProvider.removeUserFromGroup(
                    widget.groupId, user.id); // Use await and get bool

                if (isRemoved == true) {
                  // Check if isRemoved is true
                  setState(() {
                    groupMemberIds.remove(user.id);
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("User not was removed from this group ")));
                }
                Navigator.of(context).pop(true);
                widget.onGroupUpdated(widget.groupModel, groupMemberIds);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    ).then((confirmed) {
      if (confirmed != null && confirmed) {
        setState(() {});
      }
    });
  }

  // Method to add Users
  Future<bool> _updateUsersGroup(String userId, String groupId) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    bool isSuccess = false;
    try {
      //Call Websocket here to add User
      isSuccess = await chatProvider.addUserToGroup(
          groupId, userId); //Correct method name here
    } catch (error) {
      // print('error when add users group: $error');
      // if error occurs in request show a scaffoldM
    }
    return isSuccess;
  }

  @override
  Widget build(BuildContext context) {
    //Filter all users
    List<UserModel> availableUsers = widget.allUsers
        .where((user) => !groupMemberIds.contains(user.id))
        .toList();
    return AlertDialog(
      title: const Text('Manage Group'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Users in group", style: TextStyle(fontSize: 20)),
            ...widget.allUsers.map((user) {
              return Container(
                child: groupMemberIds.contains(user.id)
                    ? Container(
                        color: Colors.white12,
                        child: ListTile(
                            title: Text(user.name),
                            trailing: widget.adminId ==
                                    context.read<AuthProvider>().currentUser!.id
                                ? IconButton(
                                    //If admin user
                                    icon: const Icon(Icons.delete),
                                    onPressed: () {
                                      _showRemoveConfirmationDialog(
                                          context, user);
                                    })
                                : null),
                      )
                    : const SizedBox.shrink(),
              );
            }).toList(),
            const Divider(),
            const Text("Add a new user", style: TextStyle(fontSize: 20)),
            ...availableUsers.map((user) {
              return GestureDetector(
                child: Container(
                  color: Colors.white10,
                  child: ListTile(
                    title: Text(user.name),
                    trailing: const Icon(Icons.add),
                    onTap: () async {
                      bool isAdded =
                          await _updateUsersGroup(user.id, widget.groupId);
                      //Show new group name after editing or do some thing

                      if (isAdded == true) {
                        setState(() {
                          //After check what return of result add to selected Group id.
                          groupMemberIds.add(user.id);
                        });
                        widget.onGroupUpdated(
                            widget.groupModel, groupMemberIds);
                      }

                      //After the procced show a successfull scafold message
                    },
                  ),
                ),
              );
            }).toList(),
            ElevatedButton(
                onPressed: () {
                  _showEditGroupNameDialog(context);
                },
                child: const Text("Change name of group"))
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
