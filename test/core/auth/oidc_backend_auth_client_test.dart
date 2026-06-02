import 'package:crack_app/core/auth/oidc_backend_auth_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fetchConfig calls auth config endpoint and maps mobile OIDC settings',
    () async {
      final captured = <String, Object?>{};
      final dio = Dio(BaseOptions(baseUrl: 'http://192.168.1.9:8000'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured['path'] = options.path;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  'success': true,
                  'data': {
                    'issuer': 'https://login.jinchuan.local/realms/crack',
                    'clientId': 'crack-app-mobile',
                    'redirectUrl': 'com.jinchuan.crackapp:/oauth2redirect',
                    'scopes': ['openid', 'profile', 'email', 'offline_access'],
                    'registrationUrl':
                        'https://login.jinchuan.local/realms/crack/protocol/openid-connect/registrations',
                    'authEnabled': true,
                  },
                },
              ),
            );
          },
        ),
      );

      final config = await DioOidcBackendAuthClient(dio: dio).fetchConfig();

      expect(captured['path'], '/api/v1/auth/config');
      expect(config.oidc.issuer, 'https://login.jinchuan.local/realms/crack');
      expect(config.oidc.clientId, 'crack-app-mobile');
      expect(config.oidc.redirectUrl, 'com.jinchuan.crackapp:/oauth2redirect');
      expect(config.oidc.scopes, [
        'openid',
        'profile',
        'email',
        'offline_access',
      ]);
      expect(config.registrationUrl, contains('/registrations'));
      expect(config.authEnabled, isTrue);
    },
  );

  test('fetchCurrentUser calls /me and maps backend-confirmed user', () async {
    final captured = <String, Object?>{};
    final dio = Dio(BaseOptions(baseUrl: 'http://192.168.1.9:8000'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured['path'] = options.path;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'success': true,
                'data': {
                  'id': 'oidc-sub-1',
                  'username': 'miner01',
                  'displayName': '后端确认用户',
                  'role': 'reviewer',
                },
              },
            ),
          );
        },
      ),
    );

    final user = await DioOidcBackendAuthClient(dio: dio).fetchCurrentUser();

    expect(captured['path'], '/api/v1/me');
    expect(user.id, 'oidc-sub-1');
    expect(user.username, 'miner01');
    expect(user.displayName, '后端确认用户');
    expect(user.role, 'reviewer');
  });
}
