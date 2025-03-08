enum UserRole { user, admin }

class UserModel {
  final String id;
  final String email;
  final String name;
  final UserRole role;
  final bool isBlocked;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.isBlocked,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      name: json['name'] ?? '',
      role: _parseUserRole(json['role']),
      isBlocked: json['isBlocked'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'role': role.toString().split('.').last,
      'isBlocked': isBlocked,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    UserRole? role,
    bool? isBlocked,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      isBlocked: isBlocked ?? this.isBlocked,
    );
  }

  static UserRole _parseUserRole(String? roleStr) {
    if (roleStr == null) return UserRole.user;
    switch (roleStr) {
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.user;
    }
  }
}
