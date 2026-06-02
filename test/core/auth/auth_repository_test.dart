import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login 成功后缓存会话并可重新读取', () async {
    final remote = _FakeAuthRemoteClient();
    final store = InMemoryTokenStore();
    final repository = AuthRepository(
      remoteClient: remote,
      tokenStore: store,
    );

    final session = await repository.login(
      username: 'miner',
      password: 'secret',
    );

    expect(session.user.username, equals('miner'));
    expect(session.accessToken, equals('access-token'));
    expect(remote.loginCalls, equals(1));

    final cached = await repository.loadCachedSession();
    expect(cached, equals(session));
  });

  test('register 成功后缓存新账号会话', () async {
    final remote = _FakeAuthRemoteClient();
    final store = InMemoryTokenStore();
    final repository = AuthRepository(
      remoteClient: remote,
      tokenStore: store,
    );

    final session = await repository.register(
      username: 'newminer',
      password: 'secret123',
      displayName: '新矿工',
    );

    expect(session.user.username, equals('newminer'));
    expect(remote.registerCalls, equals(1));
    expect(await repository.loadCachedSession(), equals(session));
  });

  test('DioAuthRemoteClient 将重复用户名响应转换为友好错误', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 409,
                data: {
                  'success': false,
                  'errorCode': 'USERNAME_EXISTS',
                  'message': '用户名已存在，请换一个用户名',
                },
              ),
              type: DioExceptionType.badResponse,
            ),
          );
        },
      ),
    );

    await expectLater(
      DioAuthRemoteClient(dio).register(
        username: 'miner',
        password: 'secret123',
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          '用户名已存在，请换一个用户名',
        ),
      ),
    );
  });

  test('continueAsGuest 离线生成唯一访客会话并缓存', () async {
    final remote = _FakeAuthRemoteClient();
    final store = InMemoryTokenStore();
    final repository = AuthRepository(
      remoteClient: remote,
      tokenStore: store,
      guestIdFactory: () => 'guest_20260513_x7k9',
    );

    final session = await repository.continueAsGuest(tryRemote: false);

    expect(session.accessToken, equals('guest-local-guest_20260513_x7k9'));
    expect(session.user.username, equals('guest_20260513_x7k9'));
    expect(session.user.displayName, equals('访客 x7k9'));
    expect(await repository.loadCachedSession(), equals(session));
  });

  test('accessTokenForOnlineRequest 会把本地访客升级成服务端访客会话', () async {
    final remote = _FakeAuthRemoteClient();
    final store = InMemoryTokenStore();
    final repository = AuthRepository(
      remoteClient: remote,
      tokenStore: store,
      guestIdFactory: () => 'guest_20260513_x7k9',
    );
    await repository.continueAsGuest(tryRemote: false);

    final token = await repository.accessTokenForOnlineRequest();

    expect(token, equals('guest-access'));
    expect(remote.guestCalls, equals(['guest_20260513_x7k9']));
    expect((await repository.loadCachedSession())!.accessToken, 'guest-access');
  });

  test('logout 清除本地 token，不影响离线功能判断', () async {
    final repository = AuthRepository(
      remoteClient: _FakeAuthRemoteClient(),
      tokenStore: InMemoryTokenStore(),
    );

    await repository.login(username: 'miner', password: 'secret');
    await repository.logout();

    expect(await repository.loadCachedSession(), isNull);
    expect(await repository.canUseOfflineFeatures(), isTrue);
  });
}

class _FakeAuthRemoteClient implements AuthRemoteClient {
  int loginCalls = 0;
  int registerCalls = 0;
  final guestCalls = <String?>[];

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    loginCalls++;
    return AuthSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      expiresAt: DateTime.utc(2026, 5, 4, 12),
      user: AuthUser(
        id: 'u1',
        username: username,
        displayName: '矿山人员',
        role: 'operator',
      ),
    );
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
    String? email,
  }) async {
    registerCalls++;
    return AuthSession(
      accessToken: 'registered-access-token',
      refreshToken: 'registered-refresh-token',
      expiresAt: DateTime.utc(2026, 5, 13, 12),
      user: AuthUser(
        id: 'u-new',
        username: username,
        displayName: displayName ?? username,
        role: 'operator',
      ),
    );
  }

  @override
  Future<AuthSession> guest({
    String? guestId,
    String? displayName,
  }) async {
    guestCalls.add(guestId);
    return AuthSession(
      accessToken: 'guest-access',
      refreshToken: 'guest-refresh',
      expiresAt: DateTime.utc(2026, 5, 13, 12),
      user: AuthUser(
        id: guestId ?? 'guest-generated',
        username: guestId ?? 'guest-generated',
        displayName: displayName ?? '访客 x7k9',
        role: 'operator',
      ),
    );
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    throw UnimplementedError();
  }
}
