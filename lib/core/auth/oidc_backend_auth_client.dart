/// 企业 OIDC 后端认证确认客户端。
library;

import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/oidc_auth_config.dart';
import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

/// 后端返回的移动端 OIDC 配置。
class BackendOidcConfig extends Equatable {
  /// 创建后端 OIDC 配置。
  const BackendOidcConfig({
    required this.oidc,
    required this.registrationUrl,
    required this.authEnabled,
  });

  /// 从 JSON 创建配置。
  factory BackendOidcConfig.fromJson(Map<String, dynamic> json) {
    final scopes = json['scopes'] as List<dynamic>? ?? const <dynamic>[];
    return BackendOidcConfig(
      oidc: OidcAuthConfig(
        issuer: json['issuer'] as String? ?? '',
        clientId:
            json['clientId'] as String? ?? EnterpriseOidcDefaults.clientId,
        redirectUrl:
            json['redirectUrl'] as String? ??
            EnterpriseOidcDefaults.redirectUrl,
        scopes: scopes.map((scope) => scope.toString()).toList(),
      ),
      registrationUrl: json['registrationUrl'] as String? ?? '',
      authEnabled: json['authEnabled'] as bool? ?? true,
    );
  }

  /// OIDC 登录配置。
  final OidcAuthConfig oidc;

  /// 企业身份服务注册链接。
  final String registrationUrl;

  /// 后端是否启用真实 OIDC 校验。
  final bool authEnabled;

  @override
  List<Object?> get props => [oidc, registrationUrl, authEnabled];
}

/// OIDC 后端确认客户端抽象。
abstract interface class OidcBackendAuthClient {
  /// 读取后端公开的移动端 OIDC 配置。
  Future<BackendOidcConfig> fetchConfig();

  /// 读取当前用户，后端会校验 Bearer token 并写入 users 快照。
  Future<AuthUser> fetchCurrentUser();
}

/// 基于 Dio 的 OIDC 后端确认客户端。
class DioOidcBackendAuthClient implements OidcBackendAuthClient {
  /// 创建后端确认客户端。
  const DioOidcBackendAuthClient({required Dio dio}) : _dio = dio;

  final Dio _dio;

  @override
  Future<BackendOidcConfig> fetchConfig() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/auth/config',
    );
    return BackendOidcConfig.fromJson(_data(response.data));
  }

  @override
  Future<AuthUser> fetchCurrentUser() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/me');
    return AuthUser.fromJson(_data(response.data));
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    if (body == null) {
      throw StateError('后端认证响应为空');
    }
    return (body['data'] as Map<String, dynamic>?) ?? body;
  }
}
