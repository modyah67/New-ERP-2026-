class UserModel {
  final String? id;
  final String? email;
  final String? username;
  final String? password;
  final String? fullName;
  final bool isAdmin;
  final String createdAt;

  UserModel({
    this.id,
    this.email,
    this.username,
    this.password,
    this.fullName,
    this.isAdmin = false,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final rawId = map['id'];
    final id = rawId is int ? rawId.toString() : rawId?.toString();

    dynamic rawAdmin = map['is_admin'];
    bool isAdmin;
    if (rawAdmin is bool) {
      isAdmin = rawAdmin;
    } else if (rawAdmin is int) {
      isAdmin = rawAdmin == 1;
    } else if (rawAdmin is String) {
      isAdmin = rawAdmin == '1' || rawAdmin == 'true';
    } else {
      isAdmin = false;
    }

    return UserModel(
      id: id,
      email: map['email']?.toString(),
      username: map['username']?.toString(),
      password: map['password']?.toString(),
      fullName: map['full_name']?.toString(),
      isAdmin: isAdmin,
      createdAt: map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (email != null) 'email': email,
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      'full_name': fullName,
      'is_admin': isAdmin,
      'created_at': createdAt,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? username,
    String? password,
    String? fullName,
    bool? isAdmin,
    String? createdAt,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      password: password ?? this.password,
      fullName: fullName ?? this.fullName,
      isAdmin: isAdmin ?? this.isAdmin,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
