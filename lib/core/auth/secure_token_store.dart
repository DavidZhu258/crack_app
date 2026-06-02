/// 安全 token 存储
library;

import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 基于 flutter_secure_storage 的会话存储。
class SecureTokenStore implements TokenStore {
  /// 创建安全存储
  const SecureTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _sessionKey = 'auth_session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> saveSession(AuthSession session) {
    return _storage.write(
      key: _sessionKey,
      value: encodeSession(session),
    );
  }

  @override
  Future<AuthSession?> readSession() async {
    final value = await _storage.read(key: _sessionKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return decodeSession(value);
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _sessionKey);
  }
}
