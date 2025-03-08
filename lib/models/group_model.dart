class GroupModel {
  final String id;
  final String name;
  final List<String> memberIds;
  final String adminId;

  GroupModel({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.adminId,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      memberIds:
          json['members'] != null ? List<String>.from(json['members']) : [],
      adminId: json['adminId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'members': memberIds,
      'adminId': adminId,
    };
  }

  //copyWith
  GroupModel copyWith({
    String? id,
    String? name,
    List<String>? memberIds,
    String? adminId,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      adminId: adminId ?? this.adminId,
    );
  }
}
