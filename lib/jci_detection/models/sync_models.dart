/// 本地记录同步模型
library;

import 'package:equatable/equatable.dart';

/// 本地记录同步状态
enum SyncStatus {
  /// 仅本地保存，不需要上传
  localOnly,

  /// 等待上传
  pendingUpload,

  /// 正在上传
  uploading,

  /// 已上传
  uploaded,

  /// 上传失败，等待重试
  uploadFailed,
}

/// 同步状态扩展
extension SyncStatusX on SyncStatus {
  /// 是否需要上传/重试
  bool get needsUpload {
    return this == SyncStatus.pendingUpload || this == SyncStatus.uploadFailed;
  }

  /// 展示名称
  String get displayName {
    switch (this) {
      case SyncStatus.localOnly:
        return '仅本地';
      case SyncStatus.pendingUpload:
        return '待同步';
      case SyncStatus.uploading:
        return '同步中';
      case SyncStatus.uploaded:
        return '已同步';
      case SyncStatus.uploadFailed:
        return '同步失败';
    }
  }
}

/// 出站队列项类型
enum OutboxItemType {
  /// 上传记录 JSON
  uploadRecord,

  /// 上传图片
  uploadImage,

  /// 上传人工复核
  uploadReview,
}

/// 出站队列项
class OutboxItem extends Equatable {
  /// 创建队列项
  const OutboxItem({
    required this.id,
    required this.recordId,
    required this.type,
    required this.createdAt,
    this.payloadPath,
    this.attemptCount = 0,
    this.nextRetryAt,
    this.lastError,
  });

  /// 队列项 ID
  final String id;

  /// 本地记录 ID
  final String recordId;

  /// 队列项类型
  final OutboxItemType type;

  /// 载荷路径
  final String? payloadPath;

  /// 尝试次数
  final int attemptCount;

  /// 下次重试时间
  final DateTime? nextRetryAt;

  /// 最近错误
  final String? lastError;

  /// 创建时间
  final DateTime createdAt;

  @override
  List<Object?> get props => [
    id,
    recordId,
    type,
    payloadPath,
    attemptCount,
    nextRetryAt,
    lastError,
    createdAt,
  ];
}
