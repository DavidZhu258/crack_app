import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crack_app/app/app.dart';
import 'package:crack_app/app/view/home_page.dart';
import 'package:crack_app/app/view/login_page.dart';
import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:crack_app/core/auth/oidc_auth_repository.dart';
import 'package:crack_app/core/auth/oidc_backend_auth_client.dart';
import 'package:crack_app/jci_detection/services/foreground_auto_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('App', () {
    testWidgets('starts on the enterprise login page', (tester) async {
      await tester.pumpWidget(
        App(
          backendClient: _FakeBackendAuthClient(
            config: const BackendOidcConfig(
              oidc: OidcAuthConfig(
                issuer: '',
                clientId: 'crack-app-mobile',
                redirectUrl: 'com.jinchuan.crackapp:/oauth2redirect',
                scopes: ['openid', 'profile', 'email', 'offline_access'],
              ),
              registrationUrl: '',
              authEnabled: false,
            ),
          ),
          appAuthClient: _FakeOidcAppAuthClient(),
          tokenStore: InMemoryTokenStore(),
        ),
      );
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('金川矿区岩性自适应支护决策系统'), findsOneWidget);
      expect(find.text('企业账号登录'), findsOneWidget);
    });

    testWidgets('home app bar uses the Jinchuan support decision title', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(enableAutoSync: false)),
      );

      expect(find.text('金川矿区岩性自适应支护决策系统'), findsOneWidget);
      expect(find.text('岩石检测系统'), findsNothing);
    });

    testWidgets('login dialog defaults to the local development API server', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(enableAutoSync: false)),
      );

      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();

      final serverField = tester.widget<EditableText>(
        find.byType(EditableText).first,
      );
      expect(serverField.controller.text, 'http://127.0.0.1:8000');
    });

    testWidgets(
      'cloud sync dialog defaults to the local development API server',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: HomePage(enableAutoSync: false)),
        );

        await tester.tap(find.text('同步本地到网络'));
        await tester.pumpAndSettle();

        final serverField = tester.widget<EditableText>(
          find.byType(EditableText).first,
        );
        expect(serverField.controller.text, 'http://127.0.0.1:8000');
        expect(find.text('同步本地到网络'), findsWidgets);
      },
    );

    testWidgets('home login dialog stays inside the app', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(enableAutoSync: false)),
      );

      await tester.tap(find.text('账号'));
      await tester.pumpAndSettle();

      expect(find.text('登录系统'), findsOneWidget);
      expect(find.bySemanticsLabel('用户名'), findsOneWidget);
      expect(find.bySemanticsLabel('密码'), findsOneWidget);
      expect(find.text('OIDC Issuer'), findsNothing);
      expect(find.text('Client ID'), findsNothing);
      expect(find.text('Redirect URL'), findsNothing);

      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();

      expect(find.text('注册账号'), findsOneWidget);
      expect(find.bySemanticsLabel('确认密码'), findsOneWidget);
      expect(find.text('注册并登录'), findsOneWidget);
    });

    testWidgets('home shows one JCI entry and hides standalone crack entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: HomePage(enableAutoSync: false)),
      );
      await tester.pump();

      expect(find.text('掌子面 JCI 检测'), findsOneWidget);
      expect(find.text('掌子面识别、JCI 分级、支护方案与人工复核'), findsOneWidget);
      expect(find.text('开始检测'), findsOneWidget);
      expect(find.text('本地记录'), findsOneWidget);
      expect(find.text('同步本地到网络'), findsOneWidget);
      expect(find.text('已自动保存'), findsOneWidget);
      expect(find.text('裂缝检测'), findsNothing);
      expect(find.text('JCI 检测'), findsNothing);
    });

    testWidgets('home auto syncs on startup and when connectivity recovers', (
      tester,
    ) async {
      final connectivity = StreamController<List<ConnectivityResult>>();
      var syncCalls = 0;
      final service = ForegroundAutoSyncService(
        canReachServer: () async => true,
        readSession: () async => AuthSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.utc(2026, 5, 11, 12),
          user: const AuthUser(
            id: 'u1',
            username: 'miner01',
            displayName: '矿工 01',
            role: 'operator',
          ),
        ),
        syncRecords: () async {
          syncCalls++;
          return const ForegroundAutoSyncResult.synced(
            uploaded: 1,
            failed: 0,
            downloaded: 0,
          );
        },
        debounce: Duration.zero,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            autoSyncService: service,
            connectivityChanges: connectivity.stream,
          ),
        ),
      );
      await tester.pump();

      expect(syncCalls, equals(1));

      connectivity.add([ConnectivityResult.none, ConnectivityResult.wifi]);
      await tester.pump();

      expect(syncCalls, equals(2));
      await connectivity.close();
    });

    testWidgets('home sync status uses actual sync result counts', (
      tester,
    ) async {
      final service = ForegroundAutoSyncService(
        canReachServer: () async => true,
        readSession: () async => AuthSession(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.utc(2026, 5, 11, 12),
          user: const AuthUser(
            id: 'u1',
            username: 'miner01',
            displayName: '矿工 01',
            role: 'operator',
          ),
        ),
        syncRecords: () async => const ForegroundAutoSyncResult.synced(
          uploaded: 2,
          failed: 1,
          downloaded: 3,
        ),
        debounce: Duration.zero,
      );

      await tester.pumpWidget(
        MaterialApp(home: HomePage(autoSyncService: service)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('同步: 上传2 失败1 下载3'), findsOneWidget);
      expect(find.text('自动同步完成'), findsNothing);
    });

    testWidgets(
      'home account action has stable text instead of floating icon',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          const MaterialApp(home: HomePage(enableAutoSync: false)),
        );

        expect(find.text('账号'), findsOneWidget);
        expect(find.byTooltip('登录'), findsNothing);
      },
    );

    testWidgets(
      'login page never shows example issuer and offers offline use',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: LoginPage(
              backendClient: _FakeBackendAuthClient(
                config: const BackendOidcConfig(
                  oidc: OidcAuthConfig(
                    issuer: '',
                    clientId: 'crack-app-mobile',
                    redirectUrl: 'com.jinchuan.crackapp:/oauth2redirect',
                    scopes: ['openid', 'profile', 'email', 'offline_access'],
                  ),
                  registrationUrl: '',
                  authEnabled: false,
                ),
              ),
              appAuthClient: _FakeOidcAppAuthClient(),
              tokenStore: InMemoryTokenStore(),
              onLoginSuccess: (_) {},
              onOfflineUse: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('id.example.com'), findsNothing);
        expect(find.text('服务器未启用真实登录'), findsOneWidget);
        expect(find.text('离线使用'), findsOneWidget);
      },
    );

    testWidgets('login page uses backend config for native login status', (
      tester,
    ) async {
      AuthSession? loggedIn;
      final appAuthClient = _FakeOidcAppAuthClient();
      final nativeAuth = _FakeAuthRemoteClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            backendClient: _FakeBackendAuthClient(
              config: const BackendOidcConfig(
                oidc: OidcAuthConfig(
                  issuer: 'https://login.jinchuan.local/realms/crack',
                  clientId: 'crack-app-mobile',
                  redirectUrl: 'com.jinchuan.crackapp:/oauth2redirect',
                  scopes: ['openid', 'profile', 'email', 'offline_access'],
                ),
                registrationUrl:
                    'https://login.jinchuan.local/realms/crack/protocol/openid-connect/registrations',
                authEnabled: true,
              ),
            ),
            authRemoteClient: nativeAuth,
            appAuthClient: appAuthClient,
            tokenStore: InMemoryTokenStore(),
            onLoginSuccess: (session) => loggedIn = session,
            onOfflineUse: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.bySemanticsLabel('用户名'), 'miner01');
      await tester.enterText(find.bySemanticsLabel('密码'), 'password');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(appAuthClient.loginRequests, isEmpty);
      expect(nativeAuth.loginCalls, equals(1));
      expect(loggedIn?.user.username, 'miner01');
    });

    testWidgets('login page uses in-app username password login', (
      tester,
    ) async {
      AuthSession? loggedIn;
      final appAuthClient = _FakeOidcAppAuthClient();
      final nativeAuth = _FakeAuthRemoteClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            backendClient: _FakeBackendAuthClient(
              config: const BackendOidcConfig(
                oidc: OidcAuthConfig(
                  issuer: 'https://login.jinchuan.local/realms/crack',
                  clientId: 'crack-app-mobile',
                  redirectUrl: 'com.jinchuan.crackapp:/oauth2redirect',
                  scopes: ['openid', 'profile', 'email', 'offline_access'],
                ),
                registrationUrl:
                    'https://login.jinchuan.local/realms/crack/protocol/openid-connect/registrations',
                authEnabled: true,
              ),
            ),
            authRemoteClient: nativeAuth,
            appAuthClient: appAuthClient,
            tokenStore: InMemoryTokenStore(),
            onLoginSuccess: (session) => loggedIn = session,
            onOfflineUse: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.bySemanticsLabel('用户名'), 'miner01');
      await tester.enterText(find.bySemanticsLabel('密码'), 'password');
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      expect(appAuthClient.loginRequests, isEmpty);
      expect(nativeAuth.loginCalls, equals(1));
      expect(loggedIn?.user.username, 'miner01');
    });

    testWidgets('login page registers account inside the app', (
      tester,
    ) async {
      AuthSession? loggedIn;
      final nativeAuth = _FakeAuthRemoteClient();
      await tester.pumpWidget(
        MaterialApp(
          home: LoginPage(
            backendClient: _FakeBackendAuthClient(
              config: const BackendOidcConfig(
                oidc: OidcAuthConfig(
                  issuer: 'https://login.jinchuan.local/realms/crack',
                  clientId: 'crack-app-mobile',
                  redirectUrl: 'com.jinchuan.crackapp:/oauth2redirect',
                  scopes: ['openid', 'profile', 'email', 'offline_access'],
                ),
                registrationUrl:
                    'https://login.jinchuan.local/realms/crack/protocol/openid-connect/registrations',
                authEnabled: true,
              ),
            ),
            authRemoteClient: nativeAuth,
            appAuthClient: _FakeOidcAppAuthClient(),
            tokenStore: InMemoryTokenStore(),
            onLoginSuccess: (session) => loggedIn = session,
            onOfflineUse: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('注册账号'));
      await tester.pumpAndSettle();
      await tester.enterText(find.bySemanticsLabel('用户名'), 'newminer');
      await tester.enterText(find.bySemanticsLabel('姓名'), '新矿工');
      await tester.enterText(find.bySemanticsLabel('密码'), 'secret123');
      await tester.enterText(find.bySemanticsLabel('确认密码'), 'secret123');
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();

      expect(nativeAuth.registerCalls, equals(1));
      expect(loggedIn?.user.username, 'newminer');
    });
  });
}

class _FakeBackendAuthClient implements OidcBackendAuthClient {
  _FakeBackendAuthClient({required this.config});

  final BackendOidcConfig config;
  static const currentUser = AuthUser(
    id: 'real-sub',
    username: 'miner01',
    displayName: '真实用户',
    role: 'operator',
  );

  @override
  Future<BackendOidcConfig> fetchConfig() async => config;

  @override
  Future<AuthUser> fetchCurrentUser() async => currentUser;
}

class _FakeOidcAppAuthClient implements OidcAppAuthClient {
  final loginRequests = <OidcLoginRequest>[];

  @override
  Future<OidcTokenResponse> login(OidcLoginRequest request) async {
    loginRequests.add(request);
    return const OidcTokenResponse(
      accessToken: 'real-access',
      refreshToken: 'real-refresh',
      expiresAt: '2026-05-09T10:00:00Z',
    );
  }

  @override
  Future<OidcTokenResponse> refresh(OidcRefreshRequest request) {
    throw UnimplementedError();
  }

  @override
  AuthUser userFromTokenResponse(OidcTokenResponse response) {
    return const AuthUser(
      id: 'token-sub',
      username: 'token-user',
      displayName: 'Token User',
      role: 'operator',
    );
  }
}

class _FakeAuthRemoteClient implements AuthRemoteClient {
  int loginCalls = 0;
  int registerCalls = 0;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    loginCalls++;
    return AuthSession(
      accessToken: 'native-access',
      refreshToken: 'native-refresh',
      expiresAt: DateTime.utc(2026, 5, 13, 12),
      user: AuthUser(
        id: 'native-sub',
        username: username,
        displayName: 'App 用户',
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
      accessToken: 'registered-native-access',
      refreshToken: 'registered-native-refresh',
      expiresAt: DateTime.utc(2026, 5, 13, 12),
      user: AuthUser(
        id: 'registered-sub',
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
    return AuthSession(
      accessToken: 'guest-access',
      refreshToken: 'guest-refresh',
      expiresAt: DateTime.utc(2026, 5, 13, 12),
      user: AuthUser(
        id: guestId ?? 'guest_20260513_app',
        username: guestId ?? 'guest_20260513_app',
        displayName: displayName ?? '访客 app',
        role: 'operator',
      ),
    );
  }

  @override
  Future<AuthSession> refresh(String refreshToken) {
    throw UnimplementedError();
  }
}
