class User {
  final int id;
  final String username;
  final String email;
  final String nickname;
  final String? avatar;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.nickname,
    this.avatar,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      nickname: json['nickname'] ?? json['username'],
      avatar: json['avatar'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'nickname': nickname,
      'avatar': avatar,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
