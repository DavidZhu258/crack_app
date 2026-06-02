/// 同步队列服务
library;

import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/detection_record_repository.dart';
import 'package:equatable/equatable.dart';

/// 云端同步结果
class CloudSyncResult extends Equatable {
  /// 创建同步结果
  const CloudSyncResult({required this.remoteRecordId});

  /// 云端记录 ID
  final String remoteRecordId;

  @override
  List<Object?> get props => [remoteRecordId];
}

/// 云端记录快照
class CloudRecordSnapshot extends Equatable {
  /// 创建云端记录快照
  const CloudRecordSnapshot({
    required this.remoteRecordId,
    required this.record,
    required this.syncedAt,
  });

  /// 云端记录 ID
  final String remoteRecordId;

  /// 云端返回的完整检测记录
  final JciDetectionResult record;

  /// 云端同步时间
  final DateTime syncedAt;

  @override
  List<Object?> get props => [remoteRecordId, record, syncedAt];
}

/// 云端记录客户端抽象
// ignore: one_member_abstracts
abstract interface class CloudRecordClient {
  /// 同步一条记录
  Future<CloudSyncResult> syncRecord(
    JciDetectionResult record, {
    required String idempotencyKey,
  });
}

/// 云端记录下载客户端抽象
// ignore: one_member_abstracts
abstract interface class CloudRecordDownloadClient {
  /// 下载云端记录列表
  Future<List<CloudRecordSnapshot>> downloadRecords();
}

/// 同步进度回调。
typedef SyncProgress = void Function(String message);

/// 同步摘要
class SyncSummary extends Equatable {
  /// 创建同步摘要
  const SyncSummary({
    required this.attempted,
    required this.uploaded,
    required this.failed,
  });

  /// 尝试数量
  final int attempted;

  /// 成功数量
  final int uploaded;

  /// 失败数量
  final int failed;

  @override
  List<Object?> get props => [attempted, uploaded, failed];
}

/// 本地记录同步队列
class SyncQueueService {
  /// 创建同步服务
  const SyncQueueService({
    required DetectionRecordRepository recordRepository,
    required CloudRecordClient cloudClient,
    CloudRecordDownloadClient? downloadClient,
  }) : _recordRepository = recordRepository,
       _cloudClient = cloudClient,
       _downloadClient = downloadClient;

  final DetectionRecordRepository _recordRepository;
  final CloudRecordClient _cloudClient;
  final CloudRecordDownloadClient? _downloadClient;

  /// 同步所有待上传记录
  Future<SyncSummary> syncPending({SyncProgress? onProgress}) async {
    onProgress?.call('检查本地待同步记录');
    final records = await _recordRepository.getPendingUploadRecords();
    var uploaded = 0;
    var failed = 0;

    for (final record in records) {
      onProgress?.call('上传 ${record.id} 的图片和报告');
      await _recordRepository.markUploading(record.id);
      try {
        final result = await _cloudClient.syncRecord(
          record,
          idempotencyKey: _buildIdempotencyKey(record),
        );
        await _recordRepository.markUploaded(
          recordId: record.id,
          remoteRecordId: result.remoteRecordId,
        );
        uploaded++;
      } on Object catch (error) {
        onProgress?.call('记录 ${record.id} 同步失败');
        await _recordRepository.markUploadFailed(
          recordId: record.id,
          error: error.toString(),
        );
        failed++;
      }
    }

    return SyncSummary(
      attempted: records.length,
      uploaded: uploaded,
      failed: failed,
    );
  }

  /// 下载云端记录并写入本地仓库。
  ///
  /// 该方法用于完成“云端上传后可下载”的闭环。下载到本地的记录会标记为
  /// [SyncStatus.uploaded]，并保留云端记录 ID。
  Future<int> downloadCloudRecords({SyncProgress? onProgress}) async {
    final client = _downloadClient;
    if (client == null) {
      return 0;
    }

    onProgress?.call('下载云端记录');
    final snapshots = await client.downloadRecords();
    for (final snapshot in snapshots) {
      final existing = await _recordRepository.getRecord(snapshot.record.id);
      final merged = _mergeDownloadedRecord(existing, snapshot.record);
      await _recordRepository.save(
        merged.copyWith(
          syncStatus: SyncStatus.uploaded,
          remoteRecordId: snapshot.remoteRecordId,
          syncError: '',
          updatedAt: snapshot.syncedAt,
        ),
      );
    }
    return snapshots.length;
  }

  /// 先上传待同步记录，再下载云端记录。
  Future<SyncSummary> syncAll() async {
    final uploadSummary = await syncPending();
    await downloadCloudRecords();
    return uploadSummary;
  }

  String _buildIdempotencyKey(JciDetectionResult record) {
    final updatedAt = record.updatedAt ?? record.timestamp;
    return '${record.id}_${updatedAt.toIso8601String()}';
  }

  JciDetectionResult _mergeDownloadedRecord(
    JciDetectionResult? existing,
    JciDetectionResult downloaded,
  ) {
    if (existing == null) {
      return downloaded;
    }
    return downloaded.copyWith(
      image1Path: existing.image1Path,
      image2Path: existing.image2Path,
      resultImage1: downloaded.resultImage1.isEmpty
          ? existing.resultImage1
          : downloaded.resultImage1,
      resultImage2: downloaded.resultImage2.isEmpty
          ? existing.resultImage2
          : downloaded.resultImage2,
      reportPath: existing.reportPath ?? downloaded.reportPath,
      extractedParams: downloaded.extractedParams.copyWith(
        resultImage1: downloaded.extractedParams.resultImage1.isEmpty
            ? existing.extractedParams.resultImage1
            : downloaded.extractedParams.resultImage1,
        resultImage2: downloaded.extractedParams.resultImage2.isEmpty
            ? existing.extractedParams.resultImage2
            : downloaded.extractedParams.resultImage2,
      ),
    );
  }
}
