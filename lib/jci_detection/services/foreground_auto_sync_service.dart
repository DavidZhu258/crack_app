/// 前台自动同步服务。
library;

import 'package:crack_app/core/auth/auth_models.dart';
import 'package:equatable/equatable.dart';

/// 前台自动同步状态。
enum ForegroundAutoSyncStatus {
  /// 已同步。
  synced,

  /// 服务器或网络不可达。
  offline,

  /// 需要登录后才能同步。
  needsLogin,

  /// 已跳过，例如正在同步或防抖窗口内。
  skipped,

  /// 同步失败。
  failed,
}

/// 前台自动同步结果。
class ForegroundAutoSyncResult extends Equatable {
  /// 创建同步结果。
  const ForegroundAutoSyncResult._({
    required this.status,
    required this.uploaded,
    required this.failed,
    required this.downloaded,
    required this.message,
  });

  /// 已完成同步。
  const ForegroundAutoSyncResult.synced({
    required int uploaded,
    required int failed,
    required int downloaded,
    String message = '',
  }) : this._(
         status: ForegroundAutoSyncStatus.synced,
         uploaded: uploaded,
         failed: failed,
         downloaded: downloaded,
         message: message,
       );

  /// 网络不可用。
  const ForegroundAutoSyncResult.offline([String message = '网络不可达'])
    : this._(
        status: ForegroundAutoSyncStatus.offline,
        uploaded: 0,
        failed: 0,
        downloaded: 0,
        message: message,
      );

  /// 需要登录。
  const ForegroundAutoSyncResult.needsLogin([String message = '待登录后同步'])
    : this._(
        status: ForegroundAutoSyncStatus.needsLogin,
        uploaded: 0,
        failed: 0,
        downloaded: 0,
        message: message,
      );

  /// 跳过同步。
  const ForegroundAutoSyncResult.skipped([String message = '同步已跳过'])
    : this._(
        status: ForegroundAutoSyncStatus.skipped,
        uploaded: 0,
        failed: 0,
        downloaded: 0,
        message: message,
      );

  /// 同步失败。
  const ForegroundAutoSyncResult.failed(String message)
    : this._(
        status: ForegroundAutoSyncStatus.failed,
        uploaded: 0,
        failed: 0,
        downloaded: 0,
        message: message,
      );

  /// 状态。
  final ForegroundAutoSyncStatus status;

  /// 上传成功数量。
  final int uploaded;

  /// 上传失败数量。
  final int failed;

  /// 下载数量。
  final int downloaded;

  /// 附加消息。
  final String message;

  /// 是否执行了真实同步。
  bool get didSync => status == ForegroundAutoSyncStatus.synced;

  @override
  List<Object?> get props => [status, uploaded, failed, downloaded, message];
}

/// 当前服务器是否可达。
typedef CanReachServer = Future<bool> Function();

/// 读取当前登录会话。
typedef ReadAuthSession = Future<AuthSession?> Function();

/// 执行上传和下载。
typedef SyncRecords = Future<ForegroundAutoSyncResult> Function();

/// 前台自动同步服务。
///
/// 该服务不做后台常驻任务，只响应 App 前台生命周期和网络恢复事件。
class ForegroundAutoSyncService {
  /// 创建前台自动同步服务。
  ForegroundAutoSyncService({
    required CanReachServer canReachServer,
    required ReadAuthSession readSession,
    required SyncRecords syncRecords,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 30),
  }) : _canReachServer = canReachServer,
       _readSession = readSession,
       _syncRecords = syncRecords,
       _clock = clock ?? DateTime.now;

  final CanReachServer _canReachServer;
  final ReadAuthSession _readSession;
  final SyncRecords _syncRecords;
  final DateTime Function() _clock;

  /// 防抖间隔。
  final Duration debounce;

  DateTime? _lastAttemptAt;
  bool _isSyncing = false;

  /// 尝试执行一次前台同步。
  Future<ForegroundAutoSyncResult> syncNow({bool force = false}) async {
    if (_isSyncing) {
      return const ForegroundAutoSyncResult.skipped('同步正在进行');
    }

    final now = _clock();
    final lastAttemptAt = _lastAttemptAt;
    if (!force &&
        lastAttemptAt != null &&
        now.difference(lastAttemptAt) < debounce) {
      return const ForegroundAutoSyncResult.skipped('同步触发过于频繁');
    }

    _isSyncing = true;
    try {
      final reachable = await _canReachServer();
      if (!reachable) {
        return const ForegroundAutoSyncResult.offline();
      }

      _lastAttemptAt = now;

      final session = await _readSession();
      if (session == null) {
        return const ForegroundAutoSyncResult.needsLogin();
      }

      return await _syncRecords();
    } on Object catch (error) {
      final message = error.toString();
      if (_looksLikeAuthFailure(message)) {
        return ForegroundAutoSyncResult.needsLogin(message);
      }
      return ForegroundAutoSyncResult.failed(message);
    } finally {
      _isSyncing = false;
    }
  }

  bool _looksLikeAuthFailure(String message) {
    final lower = message.toLowerCase();
    return message.contains('没有可刷新的') ||
        lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden');
  }
}
