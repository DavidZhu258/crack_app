import 'package:crack_app/core/api/api_client.dart';
import 'package:crack_app/core/app_branding.dart';
import 'package:crack_app/core/auth/auth_models.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:crack_app/core/auth/oidc_auth_repository.dart'
    show OidcAppAuthClient;
import 'package:crack_app/core/auth/oidc_backend_auth_client.dart';
import 'package:crack_app/core/auth/secure_token_store.dart';
import 'package:flutter/material.dart';

/// 企业登录页。
class LoginPage extends StatefulWidget {
  /// 创建企业登录页。
  const LoginPage({
    required this.onLoginSuccess,
    required this.onOfflineUse,
    super.key,
    this.serverBaseUrl = EnterpriseApiDefaults.baseUrl,
    this.backendClient,
    this.appAuthClient,
    this.authRemoteClient,
    this.tokenStore,
    this.openRegistrationUrl,
  });

  /// API 服务地址。
  final String serverBaseUrl;

  /// 后端 OIDC 配置与用户确认客户端。
  final OidcBackendAuthClient? backendClient;

  /// OIDC AppAuth 客户端。
  ///
  /// 保留给旧测试/调用方兼容；当前登录页不再用它打开系统浏览器。
  final OidcAppAuthClient? appAuthClient;

  /// App 内用户名密码认证客户端。
  final AuthRemoteClient? authRemoteClient;

  /// 安全会话存储。
  final TokenStore? tokenStore;

  /// 注册页打开函数，便于测试替换。
  final Future<void> Function(String url)? openRegistrationUrl;

  /// 登录成功回调。
  final ValueChanged<AuthSession> onLoginSuccess;

  /// 离线使用回调。
  final VoidCallback onOfflineUse;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late Future<BackendOidcConfig> _configFuture;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoggingIn = false;
  bool _isRegistering = false;
  bool _isGuestEntering = false;

  @override
  void initState() {
    super.initState();
    _configFuture = _fetchConfig();
  }

  OidcBackendAuthClient get _backendClient {
    return widget.backendClient ??
        DioOidcBackendAuthClient(
          dio: ApiClient(baseUrl: widget.serverBaseUrl).dio,
        );
  }

  AuthRemoteClient get _authRemoteClient {
    return widget.authRemoteClient ??
        DioAuthRemoteClient(ApiClient(baseUrl: widget.serverBaseUrl).dio);
  }

  TokenStore get _tokenStore {
    return widget.tokenStore ?? const SecureTokenStore();
  }

  Future<BackendOidcConfig> _fetchConfig() {
    return _backendClient.fetchConfig();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _reloadConfig() {
    setState(() {
      _configFuture = _fetchConfig();
    });
  }

  Future<void> _login(BackendOidcConfig backendConfig) async {
    if (!_canLogin(backendConfig)) {
      return;
    }
    setState(() => _isLoggingIn = true);
    try {
      final repository = AuthRepository(
        remoteClient: _authRemoteClient,
        tokenStore: _tokenStore,
      );
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      if (username.isEmpty || password.isEmpty) {
        throw StateError('请输入用户名和密码');
      }
      final session = await repository.login(
        username: username,
        password: password,
      );
      if (mounted) {
        widget.onLoginSuccess(session);
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败: ${_friendlyError(error)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  Future<void> _register(BackendOidcConfig backendConfig) async {
    if (!_canLogin(backendConfig)) {
      return;
    }
    setState(() => _isLoggingIn = true);
    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text;
      final confirmPassword = _confirmPasswordController.text;
      final displayName = _displayNameController.text.trim();
      if (username.isEmpty || password.isEmpty) {
        throw StateError('请输入用户名和密码');
      }
      if (password.length < 6) {
        throw StateError('密码至少 6 位');
      }
      if (password != confirmPassword) {
        throw StateError('两次输入的密码不一致');
      }
      final repository = AuthRepository(
        remoteClient: _authRemoteClient,
        tokenStore: _tokenStore,
      );
      final session = await repository.register(
        username: username,
        password: password,
        displayName: displayName.isEmpty ? null : displayName,
      );
      if (mounted) {
        widget.onLoginSuccess(session);
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('注册失败: ${_friendlyError(error)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingIn = false);
      }
    }
  }

  Future<void> _continueAsGuest() async {
    setState(() => _isGuestEntering = true);
    try {
      final repository = AuthRepository(
        remoteClient: _authRemoteClient,
        tokenStore: _tokenStore,
      );
      final session = await repository.continueAsGuest();
      if (mounted) {
        widget.onLoginSuccess(session);
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('访客进入失败: ${_friendlyError(error)}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGuestEntering = false);
      }
    }
  }

  bool _canLogin(BackendOidcConfig config) {
    final issuer = config.oidc.issuer.trim();
    return config.authEnabled &&
        issuer.isNotEmpty &&
        !issuer.contains('example.');
  }

  String _statusText(BackendOidcConfig config) {
    if (!config.authEnabled) {
      return '服务器未启用真实登录';
    }
    if (config.oidc.issuer.trim().isEmpty) {
      return '服务器未返回登录服务配置';
    }
    if (config.oidc.issuer.contains('example.')) {
      return '服务器返回了无效的示例登录地址';
    }
    return '登录服务已连接';
  }

  Color _statusColor(BackendOidcConfig config) {
    return _canLogin(config) ? Colors.green : Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.verified_user, size: 56),
                  const SizedBox(height: 20),
                  Text(
                    appSystemName,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '企业账号登录',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 24),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).dividerColor,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FutureBuilder<BackendOidcConfig>(
                        future: _configFuture,
                        builder: (context, snapshot) {
                          final config = snapshot.data;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ServerAddressRow(
                                serverBaseUrl: widget.serverBaseUrl,
                                onRefresh: _reloadConfig,
                              ),
                              const SizedBox(height: 16),
                              if (snapshot.connectionState !=
                                  ConnectionState.done)
                                const LinearProgressIndicator()
                              else if (snapshot.hasError)
                                const _StatusBanner(
                                  icon: Icons.cloud_off,
                                  color: Colors.orange,
                                  text: '无法读取服务器登录配置',
                                )
                              else if (config != null)
                                _StatusBanner(
                                  icon: _canLogin(config)
                                      ? Icons.check_circle
                                      : Icons.info,
                                  color: _statusColor(config),
                                  text: _statusText(config),
                                ),
                              const SizedBox(height: 18),
                              TextField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '用户名',
                                  prefixIcon: Icon(Icons.person),
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_isRegistering) ...[
                                TextField(
                                  controller: _displayNameController,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: '姓名',
                                    prefixIcon: Icon(Icons.badge),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextField(
                                controller: _passwordController,
                                obscureText: true,
                                textInputAction: _isRegistering
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: '密码',
                                  prefixIcon: Icon(Icons.lock),
                                ),
                              ),
                              if (_isRegistering) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirmPasswordController,
                                  obscureText: true,
                                  textInputAction: TextInputAction.done,
                                  decoration: const InputDecoration(
                                    labelText: '确认密码',
                                    prefixIcon: Icon(Icons.lock_reset),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                onPressed:
                                    config == null ||
                                        !_canLogin(config) ||
                                        _isLoggingIn
                                    ? null
                                    : () => _isRegistering
                                          ? _register(config)
                                          : _login(config),
                                icon: _isLoggingIn
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.login),
                                label: Text(
                                  _isRegistering ? '注册并登录' : '登录',
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _isLoggingIn
                                    ? null
                                    : () => setState(() {
                                        _isRegistering = !_isRegistering;
                                      }),
                                child: Text(
                                  _isRegistering ? '已有账号，返回登录' : '注册账号',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _isLoggingIn || _isGuestEntering
                        ? null
                        : _continueAsGuest,
                    icon: _isGuestEntering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_outline),
                    label: const Text('访客进入'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isLoggingIn || _isGuestEntering
                        ? null
                        : _continueAsGuest,
                    style: TextButton.styleFrom(
                      textStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                    child: const Text('离线使用'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final text = error.toString();
  return text
      .replaceFirst('Bad state: ', '')
      .replaceFirst('Exception: ', '')
      .trim();
}

class _ServerAddressRow extends StatelessWidget {
  const _ServerAddressRow({
    required this.serverBaseUrl,
    required this.onRefresh,
  });

  final String serverBaseUrl;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.dns, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            serverBaseUrl,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: '刷新登录配置',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
