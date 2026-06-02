/// 企业 OIDC 登录配置。
library;

import 'package:equatable/equatable.dart';

/// 企业 OIDC 默认配置。
class EnterpriseOidcDefaults {
  /// OIDC issuer 由服务器 `/api/v1/auth/config` 返回。
  static const issuer = '';

  /// Flutter 移动端 public client id。
  static const clientId = 'crack-app-mobile';

  /// 移动端回调地址，需要同时配置到 Keycloak client。
  static const redirectUrl = 'com.jinchuan.crackapp:/oauth2redirect';

  /// App 默认申请的 scopes。
  static const scopes = ['openid', 'profile', 'email', 'offline_access'];

  /// 默认 OIDC 配置。
  static const config = OidcAuthConfig(
    issuer: issuer,
    clientId: clientId,
    redirectUrl: redirectUrl,
    scopes: scopes,
  );
}

/// OIDC 登录配置。
class OidcAuthConfig extends Equatable {
  /// 创建 OIDC 登录配置。
  const OidcAuthConfig({
    required this.issuer,
    required this.clientId,
    required this.redirectUrl,
    required this.scopes,
  });

  /// OIDC issuer。
  final String issuer;

  /// 移动端 public client id。
  final String clientId;

  /// App redirect URL。
  final String redirectUrl;

  /// OAuth scopes。
  final List<String> scopes;

  /// OIDC discovery URL。
  String get discoveryUrl => '$issuer/.well-known/openid-configuration';

  @override
  List<Object?> get props => [issuer, clientId, redirectUrl, scopes];
}
