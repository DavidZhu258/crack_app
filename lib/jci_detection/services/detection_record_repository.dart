/// 检测记录仓库边界
library;

import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';

/// 检测记录仓库抽象
abstract interface class DetectionRecordRepository {
  /// 保存/更新记录
  Future<void> save(JciDetectionResult result);

  /// 按 ID 获取本地记录
  Future<JciDetectionResult?> getRecord(String recordId);

  /// 获取待上传记录
  Future<List<JciDetectionResult>> getPendingUploadRecords();

  /// 标记上传中
  Future<void> markUploading(String recordId);

  /// 标记上传成功
  Future<void> markUploaded({
    required String recordId,
    required String remoteRecordId,
  });

  /// 标记上传失败
  Future<void> markUploadFailed({
    required String recordId,
    required String error,
  });
}

/// 基于现有 JSON 存储的记录仓库
class JsonDetectionRecordRepository implements DetectionRecordRepository {
  /// 创建仓库
  const JsonDetectionRecordRepository({
    required JciStorageService storageService,
  }) : _storageService = storageService;

  final JciStorageService _storageService;

  @override
  Future<void> save(JciDetectionResult result) {
    return _storageService.saveResult(
      result.copyWith(updatedAt: DateTime.now()),
    );
  }

  @override
  Future<List<JciDetectionResult>> getPendingUploadRecords() async {
    final results = await _storageService.getAllResults();
    return results.where((record) => record.syncStatus.needsUpload).toList();
  }

  @override
  Future<JciDetectionResult?> getRecord(String recordId) {
    return _storageService.getResult(recordId);
  }

  @override
  Future<void> markUploading(String recordId) async {
    final record = await _storageService.getResult(recordId);
    if (record == null) {
      return;
    }
    await save(
      record.copyWith(syncStatus: SyncStatus.uploading, syncError: ''),
    );
  }

  @override
  Future<void> markUploaded({
    required String recordId,
    required String remoteRecordId,
  }) async {
    final record = await _storageService.getResult(recordId);
    if (record == null) {
      return;
    }
    await save(
      record.copyWith(
        syncStatus: SyncStatus.uploaded,
        remoteRecordId: remoteRecordId,
        syncError: '',
      ),
    );
  }

  @override
  Future<void> markUploadFailed({
    required String recordId,
    required String error,
  }) async {
    final record = await _storageService.getResult(recordId);
    if (record == null) {
      return;
    }
    await save(
      record.copyWith(
        syncStatus: SyncStatus.uploadFailed,
        syncError: error,
      ),
    );
  }
}
