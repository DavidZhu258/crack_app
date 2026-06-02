import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:crack_app/core/auth/oidc_auth_repository.dart';
import 'package:crack_app/core/auth/oidc_backend_auth_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OidcAuthRepository', () {
    const config = OidcAuthConfig(
      issuer: 'https://login.jinchuan.local/realms/crack',
      clientId: 'crack-app-mobile',
      redirectUrl: 'com.jinchuan.crackapp:/oauth2redirect',
      scopes: ['openid', 'profile', 'email', 'offline_access'],
    );

    test('login uses authorization code with PKCE and saves session', () async {
      final tokenStore = InMemoryTokenStore();
      final appAuth = _FakeOidcAppAuthClient(
        loginResult: const OidcTokenResponse(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          idToken: 'id-1',
          expiresAt: '2026-05-07T12:00:00Z',
        ),
        userInfo: const AuthUser(
          id: 'oidc-sub-1',
          username: 'miner01',
          displayName: '张三',
          role: 'operator',
        ),
      );

      final repository = OidcAuthRepository(
        config: config,
        appAuthClient: appAuth,
        tokenStore: tokenStore,
      );

      final session = await repository.login();

      expect(session.accessToken, 'access-1');
      expect(session.refreshToken, 'refresh-1');
      expect(session.user.id, 'oidc-sub-1');
      expect(await tokenStore.readSession(), session);
      expect(appAuth.loginRequests.single.config, config);
    });

    test('loginAndVerify saves user confirmed by backend /me', () async {
      final tokenStore = InMemoryTokenStore();
      final appAuth = _FakeOidcAppAuthClient(
        loginResult: const OidcTokenResponse(
          accessToken: 'access-1',
          refreshToken: 'refresh-1',
          idToken: 'id-1',
          expiresAt: '2026-05-07T12:00:00Z',
        ),
        userInfo: const AuthUser(
          id: 'token-sub',
          username: 'token-user',
          displayName: 'Token User',
          role: 'operator',
        ),
      );
      final backend = _FakeOidcBackendAuthClient(
        currentUser: const AuthUser(
          id: 'oidc-sub-1',
          username: 'miner01',
          displayName: '后端确认用户',
          role: 'reviewer',
        ),
      );

      final repository = OidcAuthRepository(
        config: config,
        appAuthClient: appAuth,
        tokenStore: tokenStore,
      );

      final session = await repository.loginAndVerify(backendClient: backend);

      expect(backend.currentUserCalls, 1);
      expect(session.accessToken, 'access-1');
      expect(session.user.id, 'oidc-sub-1');
      expect(session.user.displayName, '后端确认用户');
      expect(session.user.role, 'reviewer');
      expect((await tokenStore.readSession())?.user, session.user);
    });

    test(
      'loginAndVerify clears provisional token when backend rejects it',
      () async {
        final tokenStore = InMemoryTokenStore();
        final appAuth = _FakeOidcAppAuthClient(
          loginResult: const OidcTokenResponse(
            accessToken: 'access-1',
            refreshToken: 'refresh-1',
            idToken: 'id-1',
            expiresAt: '2026-05-07T12:00:00Z',
          ),
          userInfo: const AuthUser(
            id: 'token-sub',
            username: 'token-user',
            displayName: 'Token User',
            role: 'operator',
          ),
        );
        final backend = _FakeOidcBackendAuthClient(
          failure: StateError('invalid bearer token'),
        );

        final repository = OidcAuthRepository(
          config: config,
          appAuthClient: appAuth,
          tokenStore: tokenStore,
        );

        await expectLater(
          repository.loginAndVerify(backendClient: backend),
          throwsA(isA<StateError>()),
        );
        expect(await tokenStore.readSession(), isNull);
      },
    );

    test('refresh uses cached refresh token and overwrites session', () async {
      final tokenStore = InMemoryTokenStore();
      await tokenStore.saveSession(
        AuthSession(
          accessToken: 'old-access',
          refreshToken: 'old-refresh',
          expiresAt: DateTime.parse('2026-05-07T10:00:00Z'),
          user: const AuthUser(
            id: 'oidc-sub-1',
            username: 'miner01',
            displayName: '张三',
            role: 'operator',
          ),
        ),
      );
      final appAuth = _FakeOidcAppAuthClient(
        refreshResult: const OidcTokenResponse(
          accessToken: 'new-access',
          refreshToken: 'new-refresh',
          idToken: 'id-2',
          expiresAt: '2026-05-07T14:00:00Z',
        ),
        userInfo: const AuthUser(
          id: 'oidc-sub-1',
          username: 'miner01',
          displayName: '张三',
          role: 'operator',
        ),
      );

      final repository = OidcAuthRepository(
        config: config,
        appAuthClient: appAuth,
        tokenStore: tokenStore,
      );

      final session = await repository.refresh();

      expect(appAuth.refreshRequests.single.refreshToken, 'old-refresh');
      expect(session.accessToken, 'new-access');
      expect(session.refreshToken, 'new-refresh');
      expect((await tokenStore.readSession())?.accessToken, 'new-access');
    });

    test(
      'accessTokenForOnlineRequest refreshes expired cached token',
      () async {
        final tokenStore = InMemoryTokenStore();
        await tokenStore.saveSession(
          AuthSession(
            accessToken: 'expired-access',
            refreshToken: 'refresh-token',
            expiresAt: DateTime.parse('2026-05-07T10:00:00Z'),
            user: const AuthUser(
              id: 'oidc-sub-1',
              username: 'miner01',
              displayName: '张三',
              role: 'operator',
            ),
          ),
        );
        final appAuth = _FakeOidcAppAuthClient(
          refreshResult: const OidcTokenResponse(
            accessToken: 'fresh-access',
            refreshToken: 'fresh-refresh',
            idToken: 'id-2',
            expiresAt: '2026-05-07T14:00:00Z',
          ),
          userInfo: const AuthUser(
            id: 'oidc-sub-1',
            username: 'miner01',
            displayName: '张三',
            role: 'operator',
          ),
        );

        final repository = OidcAuthRepository(
          config: config,
          appAuthClient: appAuth,
          tokenStore: tokenStore,
          clock: () => DateTime.parse('2026-05-07T11:00:00Z'),
        );

        final token = await repository.accessTokenForOnlineRequest();

        expect(token, 'fresh-access');
        expect(appAuth.refreshRequests, hasLength(1));
      },
    );
  });
}

class _FakeOidcBackendAuthClient implements OidcBackendAuthClient {
  _FakeOidcBackendAuthClient({
    this.currentUser,
    this.failure,
  });

  final AuthUser? currentUser;
  final Error? failure;
  int currentUserCalls = 0;

  @override
  Future<BackendOidcConfig> fetchConfig() async {
    throw UnimplementedError();
  }

  @override
  Future<AuthUser> fetchCurrentUser() async {
    currentUserCalls++;
    final error = failure;
    if (error != null) {
      throw error;
    }
    return currentUser!;
  }
}

class _FakeOidcAppAuthClient implements OidcAppAuthClient {
  _FakeOidcAppAuthClient({
    required this.userInfo,
    this.loginResult,
    this.refreshResult,
  });

  final OidcTokenResponse? loginResult;
  final OidcTokenResponse? refreshResult;
  final AuthUser userInfo;
  final loginRequests = <OidcLoginRequest>[];
  final refreshRequests = <OidcRefreshRequest>[];

  @override
  Future<OidcTokenResponse> login(OidcLoginRequest request) async {
    loginRequests.add(request);
    return loginResult!;
  }

  @override
  Future<OidcTokenResponse> refresh(OidcRefreshRequest request) async {
    refreshRequests.add(request);
    return refreshResult!;
  }

  @override
  AuthUser userFromTokenResponse(OidcTokenResponse response) => userInfo;
}
