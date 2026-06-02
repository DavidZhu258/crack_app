/// OIDC/PKCE 登录仓库
library;

import 'dart:convert';

import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:crack_app/core/auth/oidc_auth_config.dart';
import 'package:crack_app/core/auth/oidc_backend_auth_client.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_appauth/flutter_appauth.dart';

export 'package:crack_app/core/auth/oidc_auth_config.dart';

/// OIDC 登录请求。
class OidcLoginRequest extends Equatable {
  /// 创建 OIDC 登录请求。
  const OidcLoginRequest({required this.config});

  /// 登录配置。
  final OidcAuthConfig config;

  @override
  List<Object?> get props => [config];
}

/// OIDC refresh 请求。
class OidcRefreshRequest extends Equatable {
  /// 创建 OIDC refresh 请求。
  const OidcRefreshRequest({
    required this.config,
    required this.refreshToken,
  });

  /// 登录配置。
  final OidcAuthConfig config;

  /// refresh token。
  final String refreshToken;

  @override
  List<Object?> get props => [config, refreshToken];
}

/// OIDC token 响应。
class OidcTokenResponse extends Equatable {
  /// 创建 token 响应。
  const OidcTokenResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.idToken,
  });

  /// access token。
  final String accessToken;

  /// refresh token。
  final String refreshToken;

  /// id token。
  final String? idToken;

  /// ISO-8601 过期时间。
  final String expiresAt;

  /// 转为 AuthSession。
  AuthSession toSession(AuthUser user) {
    return AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.parse(expiresAt),
      user: user,
    );
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, idToken, expiresAt];
}

/// AppAuth 客户端抽象，便于单测替换。
abstract interface class OidcAppAuthClient {
  /// 执行授权码 + PKCE 登录。
  Future<OidcTokenResponse> login(OidcLoginRequest request);

  /// 使用 refresh token 刷新会话。
  Future<OidcTokenResponse> refresh(OidcRefreshRequest request);

  /// 从 token claims 映射 App 用户。
  AuthUser userFromTokenResponse(OidcTokenResponse response);
}

/// 基于 flutter_appauth 的 OIDC 客户端。
class FlutterOidcAppAuthClient implements OidcAppAuthClient {
  /// 创建 AppAuth 客户端。
  FlutterOidcAppAuthClient({FlutterAppAuth? appAuth})
    : _appAuth = appAuth ?? const FlutterAppAuth();

  final FlutterAppAuth _appAuth;

  @override
  Future<OidcTokenResponse> login(OidcLoginRequest request) async {
    final config = request.config;
    final response = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        config.clientId,
        config.redirectUrl,
        discoveryUrl: config.discoveryUrl,
        scopes: config.scopes,
      ),
    );
    if (response.accessToken == null) {
      throw StateError('OIDC 登录未返回 access token');
    }
    return _fromAuthorizationResponse(response);
  }

  @override
  Future<OidcTokenResponse> refresh(OidcRefreshRequest request) async {
    final config = request.config;
    final response = await _appAuth.token(
      TokenRequest(
        config.clientId,
        config.redirectUrl,
        discoveryUrl: config.discoveryUrl,
        refreshToken: request.refreshToken,
        scopes: config.scopes,
      ),
    );
    if (response.accessToken == null) {
      throw StateError('OIDC 刷新未返回 access token');
    }
    return _fromTokenResponse(
      response,
      fallbackRefreshToken: request.refreshToken,
    );
  }

  @override
  AuthUser userFromTokenResponse(OidcTokenResponse response) {
    final claims =
        _decodeJwtPayload(response.idToken) ??
        _decodeJwtPayload(response.accessToken) ??
        const <String, dynamic>{};
    final subject = claims['sub'] as String? ?? '';
    final username =
        claims['preferred_username'] as String? ??
        claims['email'] as String? ??
        subject;
    final displayName =
        claims['name'] as String? ??
        claims['given_name'] as String? ??
        username;
    return AuthUser(
      id: subject,
      username: username,
      displayName: displayName,
      role: _firstRole(claims),
    );
  }

  OidcTokenResponse _fromAuthorizationResponse(
    AuthorizationTokenResponse response,
  ) {
    return OidcTokenResponse(
      accessToken: response.accessToken!,
      refreshToken: response.refreshToken ?? '',
      idToken: response.idToken,
      expiresAt: _expiresAt(response.accessTokenExpirationDateTime),
    );
  }

  OidcTokenResponse _fromTokenResponse(
    TokenResponse response, {
    required String fallbackRefreshToken,
  }) {
    return OidcTokenResponse(
      accessToken: response.accessToken!,
      refreshToken: response.refreshToken ?? fallbackRefreshToken,
      idToken: response.idToken,
      expiresAt: _expiresAt(response.accessTokenExpirationDateTime),
    );
  }

  String _expiresAt(DateTime? value) {
    return (value ?? DateTime.now().add(const Duration(hours: 1)))
        .toUtc()
        .toIso8601String();
  }

  Map<String, dynamic>? _decodeJwtPayload(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }
    try {
      final normalized = base64Url.normalize(parts[1]);
      return jsonDecode(
            utf8.decode(base64Url.decode(normalized)),
          )
          as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  String _firstRole(Map<String, dynamic> claims) {
    final realmAccess = claims['realm_access'] as Map<String, dynamic>?;
    final realmRoles = realmAccess?['roles'] as List<dynamic>?;
    if (realmRoles != null && realmRoles.isNotEmpty) {
      return realmRoles.first.toString();
    }
    return 'operator';
  }
}

/// OIDC 登录仓库。
class OidcAuthRepository {
  /// 创建 OIDC 登录仓库。
  const OidcAuthRepository({
    required OidcAuthConfig config,
    required OidcAppAuthClient appAuthClient,
    required TokenStore tokenStore,
    DateTime Function()? clock,
    this.refreshSkew = const Duration(minutes: 1),
  }) : _config = config,
       _appAuthClient = appAuthClient,
       _tokenStore = tokenStore,
       _clock = clock;

  final OidcAuthConfig _config;
  final OidcAppAuthClient _appAuthClient;
  final TokenStore _tokenStore;
  final DateTime Function()? _clock;

  /// 到期前多久主动刷新。
  final Duration refreshSkew;

  DateTime get _now => _clock?.call() ?? DateTime.now().toUtc();

  /// 登录并缓存会话。
  Future<AuthSession> login() async {
    final tokenResponse = await _appAuthClient.login(
      OidcLoginRequest(config: _config),
    );
    return _save(tokenResponse);
  }

  /// 登录后用后端 `/api/v1/me` 确认 token 和用户快照。
  Future<AuthSession> loginAndVerify({
    required OidcBackendAuthClient backendClient,
  }) async {
    final tokenResponse = await _appAuthClient.login(
      OidcLoginRequest(config: _config),
    );
    final provisional = await _save(tokenResponse);
    try {
      final user = await backendClient.fetchCurrentUser();
      final verified = AuthSession(
        accessToken: provisional.accessToken,
        refreshToken: provisional.refreshToken,
        expiresAt: provisional.expiresAt,
        user: user,
      );
      await _tokenStore.saveSession(verified);
      return verified;
    } catch (_) {
      await _tokenStore.clear();
      rethrow;
    }
  }

  /// 读取本地会话。
  Future<AuthSession?> loadCachedSession() => _tokenStore.readSession();

  /// 刷新并缓存会话。
  Future<AuthSession> refresh() async {
    final cached = await _tokenStore.readSession();
    if (cached == null || cached.refreshToken.isEmpty) {
      throw StateError('没有可刷新的 OIDC 会话');
    }
    final tokenResponse = await _appAuthClient.refresh(
      OidcRefreshRequest(config: _config, refreshToken: cached.refreshToken),
    );
    return _save(tokenResponse);
  }

  /// 获取线上请求 token；过期时先 refresh。
  Future<String?> accessTokenForOnlineRequest() async {
    final cached = await _tokenStore.readSession();
    if (cached == null) {
      return null;
    }
    if (cached.expiresAt.toUtc().isAfter(_now.add(refreshSkew))) {
      return cached.accessToken;
    }
    final refreshed = await refresh();
    return refreshed.accessToken;
  }

  /// 退出登录。
  Future<void> logout() => _tokenStore.clear();

  /// 未登录也允许离线检测。
  Future<bool> canUseOfflineFeatures() async => true;

  Future<AuthSession> _save(OidcTokenResponse tokenResponse) async {
    final user = _appAuthClient.userFromTokenResponse(tokenResponse);
    final session = tokenResponse.toSession(user);
    await _tokenStore.saveSession(session);
    return session;
  }
}
