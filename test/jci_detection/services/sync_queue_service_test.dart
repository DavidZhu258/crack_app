import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/detection_record_repository.dart';
import 'package:crack_app/jci_detection/services/sync_queue_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncPending 上传待同步记录并写入云端 ID', () async {
    final record = _result(id: 'r1', syncStatus: SyncStatus.pendingUpload);
    final repository = _FakeDetectionRecordRepository([record]);
    final cloudClient = _FakeCloudRecordClient(remoteRecordId: 'cloud-r1');
    final service = SyncQueueService(
      recordRepository: repository,
      cloudClient: cloudClient,
    );

    final summary = await service.syncPending();

    expect(summary.attempted, equals(1));
    expect(summary.uploaded, equals(1));
    expect(summary.failed, equals(0));
    expect(repository.records['r1']!.syncStatus, equals(SyncStatus.uploaded));
    expect(repository.records['r1']!.remoteRecordId, equals('cloud-r1'));
    expect(cloudClient.lastIdempotencyKey, contains('r1'));
  });

  test('syncPending 上传失败时保留本地记录并标记失败原因', () async {
    final record = _result(id: 'r2', syncStatus: SyncStatus.pendingUpload);
    final repository = _FakeDetectionRecordRepository([record]);
    final cloudClient = _FakeCloudRecordClient(error: StateError('timeout'));
    final service = SyncQueueService(
      recordRepository: repository,
      cloudClient: cloudClient,
    );

    final summary = await service.syncPending();

    expect(summary.attempted, equals(1));
    expect(summary.uploaded, equals(0));
    expect(summary.failed, equals(1));
    expect(repository.records.containsKey('r2'), isTrue);
    expect(
      repository.records['r2']!.syncStatus,
      equals(SyncStatus.uploadFailed),
    );
    expect(repository.records['r2']!.syncError, contains('timeout'));
  });

  test('downloadCloudRecords 下载云端记录并保存为已上传状态', () async {
    final cloudRecord = _result(id: 'r3', syncStatus: SyncStatus.uploaded)
        .copyWith(
          remoteRecordId: 'cloud-r3',
          manualReview: ManualReview(
            acceptedRecognitionResult: true,
            reviewerName: '张三',
            reviewedAt: DateTime.utc(2026, 5, 7, 10),
          ),
        );
    final repository = _FakeDetectionRecordRepository([]);
    final cloudClient = _FakeCloudRecordClient(
      snapshots: [
        CloudRecordSnapshot(
          remoteRecordId: 'cloud-r3',
          record: cloudRecord,
          syncedAt: DateTime.utc(2026, 5, 7, 10, 1),
        ),
      ],
    );
    final service = SyncQueueService(
      recordRepository: repository,
      cloudClient: cloudClient,
      downloadClient: cloudClient,
    );

    final downloaded = await service.downloadCloudRecords();

    expect(downloaded, equals(1));
    expect(repository.records['r3'], isNotNull);
    expect(repository.records['r3']!.syncStatus, equals(SyncStatus.uploaded));
    expect(
      repository.records['r3']!.remoteRecordId,
      equals('cloud-r3'),
    );
    expect(repository.records['r3']!.manualReview, isNotNull);
  });
}

JciDetectionResult _result({
  required String id,
  required SyncStatus syncStatus,
}) {
  final bytes = Uint8List.fromList([1, 2, 3]);
  return JciDetectionResult(
    id: id,
    timestamp: DateTime.utc(2026, 5, 4, 12),
    image1Path: '/tmp/a.jpg',
    image2Path: '/tmp/b.jpg',
    resultImage1: bytes,
    resultImage2: bytes,
    extractedParams: ExtractedParameters(
      rqd: 80,
      jointSpacing: 20,
      jointDensity: 1,
      resultImage1: bytes,
      resultImage2: bytes,
    ),
    engineeringInfo: const EngineeringInfo(
      rockType: RockType.granite,
      depth: 598,
      waterCondition: WaterCondition.dry,
    ),
    jciResult: const JciCalculationResult(
      jciValue: 35,
      componentScores: {},
    ),
    classification: const RockClassificationResult(
      originalGrade: RockGrade.ii1,
      finalGrade: RockGrade.ii1,
    ),
    supportPlan: const SupportPlan(
      grade: RockGrade.ii1,
      methods: [],
      summary: 'test',
    ),
    syncStatus: syncStatus,
    updatedAt: DateTime.utc(2026, 5, 4, 12, 30),
  );
}

class _FakeDetectionRecordRepository implements DetectionRecordRepository {
  _FakeDetectionRecordRepository(List<JciDetectionResult> initialRecords)
    : records = {
        for (final record in initialRecords) record.id: record,
      };

  final Map<String, JciDetectionResult> records;

  @override
  Future<List<JciDetectionResult>> getPendingUploadRecords() async {
    return records.values
        .where((record) => record.syncStatus.needsUpload)
        .toList();
  }

  @override
  Future<JciDetectionResult?> getRecord(String recordId) async {
    return records[recordId];
  }

  @override
  Future<void> markUploading(String recordId) async {
    records[recordId] = records[recordId]!.copyWith(
      syncStatus: SyncStatus.uploading,
      syncError: '',
    );
  }

  @override
  Future<void> markUploaded({
    required String recordId,
    required String remoteRecordId,
  }) async {
    records[recordId] = records[recordId]!.copyWith(
      syncStatus: SyncStatus.uploaded,
      remoteRecordId: remoteRecordId,
      syncError: '',
    );
  }

  @override
  Future<void> markUploadFailed({
    required String recordId,
    required String error,
  }) async {
    records[recordId] = records[recordId]!.copyWith(
      syncStatus: SyncStatus.uploadFailed,
      syncError: error,
    );
  }

  @override
  Future<void> save(JciDetectionResult result) async {
    records[result.id] = result;
  }
}

class _FakeCloudRecordClient
    implements CloudRecordClient, CloudRecordDownloadClient {
  _FakeCloudRecordClient({this.remoteRecordId, this.error, this.snapshots});

  final String? remoteRecordId;
  final Object? error;
  final List<CloudRecordSnapshot>? snapshots;
  String? lastIdempotencyKey;

  @override
  Future<CloudSyncResult> syncRecord(
    JciDetectionResult record, {
    required String idempotencyKey,
  }) async {
    lastIdempotencyKey = idempotencyKey;
    final exception = error;
    if (exception != null) {
      if (exception is Exception) {
        throw exception;
      }
      if (exception is Error) {
        throw exception;
      }
      throw StateError(exception.toString());
    }
    return CloudSyncResult(remoteRecordId: remoteRecordId ?? record.id);
  }

  @override
  Future<List<CloudRecordSnapshot>> downloadRecords() async {
    return snapshots ?? const [];
  }
}
