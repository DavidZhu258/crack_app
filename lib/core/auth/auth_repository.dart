/// 登录仓库
library;

import 'dart:convert';
import 'dart:math';

import 'package:crack_app/core/auth/auth_models.dart';
import 'package:dio/dio.dart';

/// 认证远程接口抽象
abstract interface class AuthRemoteClient {
  /// 账号密码登录
  Future<AuthSession> login({
    required String username,
    required String password,
  });

  /// App 内注册账号并返回登录会话
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
    String? email,
  });

  /// 访客登录/注册并返回线上会话
  Future<AuthSession> guest({
    String? guestId,
    String? displayName,
  });

  /// 刷新会话
  Future<AuthSession> refresh(String refreshToken);
}

/// token/会话存储抽象
abstract interface class TokenStore {
  /// 保存会话
  Future<void> saveSession(AuthSession session);

  /// 读取会话
  Future<AuthSession?> readSession();

  /// 清除会话
  Future<void> clear();
}

/// 内存 token 存储，供测试和临时运行使用。
class InMemoryTokenStore implements TokenStore {
  AuthSession? _session;

  @override
  Future<void> saveSession(AuthSession session) async {
    _session = session;
  }

  @override
  Future<AuthSession?> readSession() async => _session;

  @override
  Future<void> clear() async {
    _session = null;
  }
}

/// Dio 认证远程客户端
class DioAuthRemoteClient implements AuthRemoteClient {
  /// 创建远程认证客户端
  const DioAuthRemoteClient(this._dio);

  final Dio _dio;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        data: {
          'username': username,
          'password': password,
        },
      );
      return _sessionFromResponse(response.data);
    } on DioException catch (error) {
      throw StateError(_authErrorMessage(error, fallback: '登录失败'));
    }
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
    String? email,
  }) async {
    final data = <String, dynamic>{
      'username': username,
      'password': password,
    };
    if (displayName != null) {
      data['displayName'] = displayName;
    }
    if (email != null) {
      data['email'] = email;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/register',
        data: data,
      );
      return _sessionFromResponse(response.data);
    } on DioException catch (error) {
      throw StateError(_authErrorMessage(error, fallback: '注册失败'));
    }
  }

  @override
  Future<AuthSession> guest({
    String? guestId,
    String? displayName,
  }) async {
    final requestData = <String, dynamic>{};
    if (guestId != null) {
      requestData['guestId'] = guestId;
    }
    if (displayName != null) {
      requestData['displayName'] = displayName;
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/guest',
        data: requestData,
      );
      return _sessionFromResponse(response.data);
    } on DioException catch (error) {
      throw StateError(_authErrorMessage(error, fallback: '访客登录失败'));
    }
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return _sessionFromResponse(response.data);
    } on DioException catch (error) {
      throw StateError(_authErrorMessage(error, fallback: '刷新登录失败'));
    }
  }

  AuthSession _sessionFromResponse(Map<String, dynamic>? body) {
    if (body == null) {
      throw StateError('认证响应为空');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? body;
    return AuthSession.fromJson(data);
  }
}

String _authErrorMessage(DioException error, {required String fallback}) {
  final body = error.response?.data;
  if (body is Map<String, dynamic>) {
    final code = body['errorCode'] as String?;
    final message = body['message'] as String?;
    if (code == 'USERNAME_EXISTS') {
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return '用户名已存在，请换一个用户名';
    }
    if (message != null && message.isNotEmpty && message != 'ok') {
      return message;
    }
    final detail = body['detail'];
    if (detail == 'username already exists') {
      return '用户名已存在，请换一个用户名';
    }
    if (detail is String && detail.isNotEmpty) {
      return detail;
    }
  }
  if (error.response?.statusCode == 409) {
    return '用户名已存在，请换一个用户名';
  }
  return fallback;
}

typedef GuestIdFactory = String Function();

/// 认证仓库
class AuthRepository {
  /// 创建认证仓库
  AuthRepository({
    required AuthRemoteClient remoteClient,
    required TokenStore tokenStore,
    GuestIdFactory? guestIdFactory,
  }) : _remoteClient = remoteClient,
       _tokenStore = tokenStore,
       _guestIdFactory = guestIdFactory ?? _generateGuestId;

  final AuthRemoteClient _remoteClient;
  final TokenStore _tokenStore;
  final GuestIdFactory _guestIdFactory;

  /// 登录并缓存会话
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final session = await _remoteClient.login(
      username: username,
      password: password,
    );
    await _tokenStore.saveSession(session);
    return session;
  }

  /// App 内注册并缓存会话
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
    String? email,
  }) async {
    final session = await _remoteClient.register(
      username: username,
      password: password,
      displayName: displayName,
      email: email,
    );
    await _tokenStore.saveSession(session);
    return session;
  }

  /// 以访客身份继续使用。离线时生成本地访客，会在联网请求前升级。
  Future<AuthSession> continueAsGuest({bool tryRemote = true}) async {
    final guestId = _guestIdFactory();
    final displayName = _guestDisplayName(guestId);
    if (tryRemote) {
      try {
        final session = await _remoteClient.guest(
          guestId: guestId,
          displayName: displayName,
        );
        await _tokenStore.saveSession(session);
        return session;
      } on Object {
        // 网络不可用时仍允许离线访客进入。
      }
    }
    final session = AuthSession(
      accessToken: 'guest-local-$guestId',
      refreshToken: 'guest-local-$guestId',
      expiresAt: DateTime.now().toUtc().add(const Duration(days: 365)),
      user: AuthUser(
        id: guestId,
        username: guestId,
        displayName: displayName,
        role: 'operator',
      ),
    );
    await _tokenStore.saveSession(session);
    return session;
  }

  /// 读取本地缓存会话
  Future<AuthSession?> loadCachedSession() => _tokenStore.readSession();

  /// 刷新会话并写回缓存
  Future<AuthSession> refresh() async {
    final cached = await _tokenStore.readSession();
    if (cached == null) {
      throw StateError('没有可刷新的登录会话');
    }
    final session = await _remoteClient.refresh(cached.refreshToken);
    await _tokenStore.saveSession(session);
    return session;
  }

  /// 获取线上请求 token；过期时先 refresh。
  Future<String?> accessTokenForOnlineRequest() async {
    final cached = await _tokenStore.readSession();
    if (cached == null) {
      return null;
    }
    if (_isLocalGuestSession(cached)) {
      final session = await _remoteClient.guest(
        guestId: cached.user.id,
        displayName: cached.user.displayName,
      );
      await _tokenStore.saveSession(session);
      return session.accessToken;
    }
    final refreshAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
    if (cached.expiresAt.toUtc().isAfter(refreshAt)) {
      return cached.accessToken;
    }
    final session = await refresh();
    return session.accessToken;
  }

  /// 退出登录
  Future<void> logout() => _tokenStore.clear();

  /// 未登录也允许离线检测。
  Future<bool> canUseOfflineFeatures() async => true;
}

bool _isLocalGuestSession(AuthSession session) {
  return session.accessToken.startsWith('guest-local-');
}

String _generateGuestId() {
  final now = DateTime.now().toUtc();
  final date =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final suffix = List.generate(
    4,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
  return 'guest_${date}_$suffix';
}

String _guestDisplayName(String guestId) {
  final suffix = guestId.split('_').last;
  return '访客 $suffix';
}

/// 将会话编码为字符串
String encodeSession(AuthSession session) => jsonEncode(session.toJson());

/// 将字符串解码为会话
AuthSession decodeSession(String encoded) {
  return AuthSession.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
}
