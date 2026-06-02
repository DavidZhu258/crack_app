import 'package:crack_app/app/view/home_page.dart';
import 'package:crack_app/app/view/login_page.dart';
import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:crack_app/core/auth/oidc_auth_repository.dart';
import 'package:crack_app/core/auth/oidc_backend_auth_client.dart';
import 'package:crack_app/l10n/l10n.dart';
import 'package:flutter/material.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    this.backendClient,
    this.appAuthClient,
    this.tokenStore,
  });

  final OidcBackendAuthClient? backendClient;
  final OidcAppAuthClient? appAuthClient;
  final TokenStore? tokenStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _AppShell(
        backendClient: backendClient,
        appAuthClient: appAuthClient,
        tokenStore: tokenStore,
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({
    this.backendClient,
    this.appAuthClient,
    this.tokenStore,
  });

  final OidcBackendAuthClient? backendClient;
  final OidcAppAuthClient? appAuthClient;
  final TokenStore? tokenStore;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _showHome = false;

  void _enterHome([AuthSession? _]) {
    setState(() => _showHome = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showHome) {
      return const HomePage();
    }
    return LoginPage(
      backendClient: widget.backendClient,
      appAuthClient: widget.appAuthClient,
      tokenStore: widget.tokenStore,
      onLoginSuccess: _enterHome,
      onOfflineUse: _enterHome,
    );
  }
}
