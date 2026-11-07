class User {
  final int id;
  final String username;
  final String email;
  final String nickname;
  /// Cloud account's authoritative IANA timezone. Null in legacy caches.
  final String? timezone;
  final String? avatar;
  final DateTime createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.nickname,
    this.avatar,
    this.timezone,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      nickname: json['nickname'] ?? json['username'],
      avatar: json['avatar'],
      timezone: json['timezone'] as String?,
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
      'timezone': timezone,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
