import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crack_app/core/api/api_client.dart';
import 'package:crack_app/core/app_branding.dart';
import 'package:crack_app/core/auth/auth_repository.dart';
import 'package:crack_app/core/auth/secure_token_store.dart';
import 'package:crack_app/core/network/network_status_service.dart';
import 'package:crack_app/jci_detection/jci_detection.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/asset_upload_client.dart';
import 'package:crack_app/jci_detection/services/cloud_record_client.dart';
import 'package:crack_app/jci_detection/services/detection_record_repository.dart';
import 'package:crack_app/jci_detection/services/foreground_auto_sync_service.dart';
import 'package:crack_app/jci_detection/services/sync_queue_service.dart';
import 'package:flutter/material.dart';

/// 主页 - 功能选择页面
///
/// 提供掌子面 JCI 检测主业务入口。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.enableAutoSync = true,
    this.autoSyncService,
    this.connectivityChanges,
  });

  /// 是否启用前台自动同步。
  final bool enableAutoSync;

  /// 前台自动同步服务，便于测试替换。
  final ForegroundAutoSyncService? autoSyncService;

  /// 网络变化流，便于测试替换。
  final Stream<List<ConnectivityResult>>? connectivityChanges;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  late Future<int> _pendingSyncCountFuture;
  ForegroundAutoSyncService? _autoSyncService;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  ForegroundAutoSyncResult? _lastAutoSyncResult;

  @override
  void initState() {
    super.initState();
    _pendingSyncCountFuture = _loadPendingSyncCount();
    if (widget.enableAutoSync) {
      WidgetsBinding.instance.addObserver(this);
      _autoSyncService =
          widget.autoSyncService ?? _buildProductionAutoSyncService();
      final changes =
          widget.connectivityChanges ?? Connectivity().onConnectivityChanged;
      _connectivitySubscription = changes.listen(_onConnectivityChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_runAutoSync());
      });
    }
  }

  @override
  void dispose() {
    unawaited(_connectivitySubscription?.cancel());
    if (widget.enableAutoSync) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runAutoSync());
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.any((result) => result != ConnectivityResult.none)) {
      unawaited(_runAutoSync());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const _SystemAppBarTitle(),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => _showLoginDialog(context),
              icon: const Icon(Icons.account_circle),
              label: const Text('账号'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<int>(
          future: _pendingSyncCountFuture,
          builder: (context, snapshot) {
            final pendingCount = snapshot.data ?? 0;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SyncStatusPanel(
                    pendingCount: pendingCount,
                    autoSyncResult: _lastAutoSyncResult,
                  ),
                  const SizedBox(height: 16),
                  _PrimaryWorkflowPanel(
                    pendingCount: pendingCount,
                    onStart: () => _navigateToJciDetection(context),
                    onHistory: () => _navigateToJciHistory(context),
                    onSync: () => _showCloudSyncDialog(context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _navigateToJciDetection(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const JciDetectionPage()),
    );
  }

  Future<void> _navigateToJciHistory(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const JciHistoryPage()),
    );
  }

  Future<int> _loadPendingSyncCount() async {
    final results = await JciStorageService().getAllResults();
    return _countPendingSync(results);
  }

  int _countPendingSync(List<JciDetectionResult> results) {
    return results
        .where(
          (result) =>
              result.syncStatus.needsUpload ||
              result.syncStatus == SyncStatus.uploading,
        )
        .length;
  }

  void _refreshPendingSyncCount() {
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingSyncCountFuture = _loadPendingSyncCount();
    });
  }

  ForegroundAutoSyncService _buildProductionAutoSyncService() {
    const tokenStore = SecureTokenStore();
    const serverBaseUrl = EnterpriseApiDefaults.baseUrl;
    return ForegroundAutoSyncService(
      canReachServer: ConnectivityNetworkStatusService(
        healthUrl: '$serverBaseUrl/health',
      ).canReachServer,
      readSession: tokenStore.readSession,
      syncRecords: () => _syncWithServer(
        serverBaseUrl: serverBaseUrl,
        tokenStore: tokenStore,
      ),
    );
  }

  Future<void> _runAutoSync() async {
    if (!widget.enableAutoSync) {
      return;
    }
    final service = _autoSyncService;
    if (service == null) {
      return;
    }

    final result = await service.syncNow();
    if (!mounted) {
      return;
    }
    setState(() {
      _lastAutoSyncResult = result;
      if (result.didSync) {
        _pendingSyncCountFuture = _loadPendingSyncCount();
      }
    });
  }

  Future<ForegroundAutoSyncResult> _syncWithServer({
    required String serverBaseUrl,
    required TokenStore tokenStore,
    SyncProgress? onProgress,
  }) async {
    onProgress?.call('检查登录状态');
    final storageService = JciStorageService();
    final authRepository = AuthRepository(
      remoteClient: DioAuthRemoteClient(
        ApiClient(baseUrl: serverBaseUrl).dio,
      ),
      tokenStore: tokenStore,
    );
    final apiClient = ApiClient(
      baseUrl: serverBaseUrl,
      tokenProvider: authRepository.accessTokenForOnlineRequest,
    );
    final cloudClient = DioCloudRecordClient(
      dio: apiClient.dio,
      assetUploadClient: DioAssetUploadClient(
        dio: apiClient.dio,
      ),
    );
    final syncService = SyncQueueService(
      recordRepository: JsonDetectionRecordRepository(
        storageService: storageService,
      ),
      cloudClient: cloudClient,
      downloadClient: cloudClient,
    );
    final uploadSummary = await syncService.syncPending(onProgress: onProgress);
    final downloaded = await syncService.downloadCloudRecords(
      onProgress: onProgress,
    );
    return ForegroundAutoSyncResult.synced(
      uploaded: uploadSummary.uploaded,
      failed: uploadSummary.failed,
      downloaded: downloaded,
    );
  }

  Future<void> _showCloudSyncDialog(BuildContext context) async {
    final serverController = TextEditingController(
      text: EnterpriseApiDefaults.baseUrl,
    );
    const tokenStore = SecureTokenStore();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          var isLoading = false;
          var progressMessage = '准备同步';
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('同步本地到网络'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: serverController,
                      enabled: !isLoading,
                      decoration: const InputDecoration(
                        labelText: '服务器地址',
                        prefixIcon: Icon(Icons.dns),
                      ),
                    ),
                    if (isLoading) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(progressMessage)),
                        ],
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            setState(() => isLoading = true);
                            try {
                              final serverBaseUrl = serverController.text
                                  .trim();
                              final syncResult = await _syncWithServer(
                                serverBaseUrl: serverBaseUrl,
                                tokenStore: tokenStore,
                                onProgress: (message) {
                                  if (context.mounted) {
                                    setState(() => progressMessage = message);
                                  }
                                },
                              );
                              final message = [
                                '上传 ${syncResult.uploaded} 条',
                                '失败 ${syncResult.failed} 条',
                                '下载 ${syncResult.downloaded} 条',
                              ].join('，');

                              if (context.mounted) {
                                Navigator.of(dialogContext).pop();
                                _lastAutoSyncResult = syncResult;
                                _refreshPendingSyncCount();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(message),
                                  ),
                                );
                              }
                            } on Exception catch (error) {
                              setState(() => isLoading = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '同步失败: ${_friendlyError(error)}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('开始同步'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      serverController.dispose();
    }
  }

  Future<void> _showLoginDialog(BuildContext context) async {
    final serverController = TextEditingController(
      text: EnterpriseApiDefaults.baseUrl,
    );
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final displayNameController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    const tokenStore = SecureTokenStore();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          var isLoading = false;
          var isGuestEntering = false;
          var isRegistering = false;
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(isRegistering ? '注册账号' : '登录系统'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder(
                        future: tokenStore.readSession(),
                        builder: (context, snapshot) {
                          final session = snapshot.data;
                          if (session == null) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.verified_user,
                                  color: Colors.green,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '当前用户: ${session.user.displayName}',
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      TextField(
                        controller: serverController,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          prefixIcon: Icon(Icons.dns),
                        ),
                      ),
                      TextField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      if (isRegistering)
                        TextField(
                          controller: displayNameController,
                          decoration: const InputDecoration(
                            labelText: '姓名',
                            prefixIcon: Icon(Icons.badge),
                          ),
                        ),
                      TextField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          prefixIcon: Icon(Icons.lock),
                        ),
                      ),
                      if (isRegistering)
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '确认密码',
                            prefixIcon: Icon(Icons.lock_reset),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => setState(() {
                            isRegistering = !isRegistering;
                          }),
                    child: Text(isRegistering ? '返回登录' : '注册账号'),
                  ),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            await tokenStore.clear();
                            if (context.mounted) {
                              Navigator.of(dialogContext).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已退出登录')),
                              );
                            }
                          },
                    child: const Text('退出'),
                  ),
                  TextButton(
                    onPressed: isLoading
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            setState(() => isLoading = true);
                            try {
                              final serverBaseUrl = serverController.text
                                  .trim();
                              final username = usernameController.text.trim();
                              final password = passwordController.text;
                              if (username.isEmpty || password.isEmpty) {
                                throw StateError('请输入用户名和密码');
                              }
                              if (isRegistering &&
                                  password != confirmPasswordController.text) {
                                throw StateError('两次输入的密码不一致');
                              }
                              final repository = AuthRepository(
                                remoteClient: DioAuthRemoteClient(
                                  ApiClient(baseUrl: serverBaseUrl).dio,
                                ),
                                tokenStore: tokenStore,
                              );
                              final session = isRegistering
                                  ? await repository.register(
                                      username: username,
                                      password: password,
                                      displayName: displayNameController.text
                                          .trim(),
                                    )
                                  : await repository.login(
                                      username: username,
                                      password: password,
                                    );
                              if (context.mounted) {
                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '已登录: ${session.user.displayName}',
                                    ),
                                  ),
                                );
                              }
                            } on Exception catch (error) {
                              setState(() => isLoading = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '${isRegistering ? '注册' : '登录'}失败: '
                                      '${_friendlyError(error)}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(isRegistering ? '注册并登录' : '登录'),
                  ),
                  OutlinedButton(
                    onPressed: isLoading || isGuestEntering
                        ? null
                        : () async {
                            setState(() => isGuestEntering = true);
                            try {
                              final serverBaseUrl = serverController.text
                                  .trim();
                              final repository = AuthRepository(
                                remoteClient: DioAuthRemoteClient(
                                  ApiClient(baseUrl: serverBaseUrl).dio,
                                ),
                                tokenStore: tokenStore,
                              );
                              final session = await repository
                                  .continueAsGuest();
                              if (context.mounted) {
                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '已以访客进入: ${session.user.displayName}',
                                    ),
                                  ),
                                );
                              }
                            } on Exception catch (error) {
                              setState(() => isGuestEntering = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '访客进入失败: ${_friendlyError(error)}',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: isGuestEntering
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('访客进入'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      serverController.dispose();
      usernameController.dispose();
      passwordController.dispose();
      displayNameController.dispose();
      confirmPasswordController.dispose();
    }
  }
}

class _SystemAppBarTitle extends StatelessWidget {
  const _SystemAppBarTitle();

  @override
  Widget build(BuildContext context) {
    return const FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        appSystemName,
        textAlign: TextAlign.center,
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

class _SyncStatusPanel extends StatelessWidget {
  const _SyncStatusPanel({
    required this.pendingCount,
    this.autoSyncResult,
  });

  final int pendingCount;
  final ForegroundAutoSyncResult? autoSyncResult;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.cloud_done,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '检测工作台',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _StatusChip(
                  icon: Icons.wifi_off,
                  label: '离线可用',
                  color: Colors.green,
                ),
                const _StatusChip(
                  icon: Icons.save,
                  label: '已自动保存',
                  color: Colors.blue,
                ),
                _StatusChip(
                  icon: pendingCount > 0 ? Icons.sync_problem : Icons.sync,
                  label: '待同步 $pendingCount 条',
                  color: pendingCount > 0 ? Colors.orange : Colors.green,
                ),
                _autoSyncChip(autoSyncResult),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoSyncChip(ForegroundAutoSyncResult? result) {
    return switch (result?.status) {
      ForegroundAutoSyncStatus.synced => _StatusChip(
        icon: result!.failed > 0 ? Icons.sync_problem : Icons.cloud_done,
        label:
            result.uploaded == 0 && result.failed == 0 && result.downloaded == 0
            ? '已检查，无需同步'
            : '同步: 上传${result.uploaded} '
                  '失败${result.failed} 下载${result.downloaded}',
        color: result.failed > 0 ? Colors.orange : Colors.green,
      ),
      ForegroundAutoSyncStatus.needsLogin => const _StatusChip(
        icon: Icons.login,
        label: '待登录后同步',
        color: Colors.orange,
      ),
      ForegroundAutoSyncStatus.offline => const _StatusChip(
        icon: Icons.cloud_off,
        label: '离线待同步',
        color: Colors.orange,
      ),
      ForegroundAutoSyncStatus.failed => const _StatusChip(
        icon: Icons.sync_problem,
        label: '自动同步失败',
        color: Colors.red,
      ),
      _ => const _StatusChip(
        icon: Icons.sync,
        label: '自动同步已开启',
        color: Colors.blue,
      ),
    };
  }
}

class _PrimaryWorkflowPanel extends StatelessWidget {
  const _PrimaryWorkflowPanel({
    required this.pendingCount,
    required this.onStart,
    required this.onHistory,
    required this.onSync,
  });

  final int pendingCount;
  final VoidCallback onStart;
  final VoidCallback onHistory;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.analytics,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '掌子面 JCI 检测',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '掌子面识别、JCI 分级、支护方案与人工复核',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始检测'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onHistory,
                    icon: const Icon(Icons.history),
                    label: const Text('本地记录'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onSync,
                    icon: Icon(
                      pendingCount > 0 ? Icons.cloud_upload : Icons.cloud_sync,
                    ),
                    label: const Text('同步本地到网络'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color.withValues(alpha: 0.28)),
      backgroundColor: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
