/// 登录与会话模型
library;

import 'package:equatable/equatable.dart';

/// 登录用户
class AuthUser extends Equatable {
  /// 创建用户
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });

  /// JSON 转模型
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      role: json['role'] as String? ?? 'operator',
    );
  }

  /// 用户 ID
  final String id;

  /// 登录名
  final String username;

  /// 显示名称
  final String displayName;

  /// 角色
  final String role;

  /// 模型转 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'displayName': displayName,
      'role': role,
    };
  }

  @override
  List<Object?> get props => [id, username, displayName, role];
}

/// 登录会话
class AuthSession extends Equatable {
  /// 创建会话
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  /// JSON 转模型
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  /// 访问 token
  final String accessToken;

  /// 刷新 token
  final String refreshToken;

  /// 过期时间
  final DateTime expiresAt;

  /// 用户信息
  final AuthUser user;

  /// 模型转 JSON
  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt, user];
}
