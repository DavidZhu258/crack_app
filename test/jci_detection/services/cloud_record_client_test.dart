import 'dart:io';
import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/asset_upload_client.dart';
import 'package:crack_app/jci_detection/services/cloud_record_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('syncRecord 通过 records/sync 上传完整记录和人工复核字段', () async {
    final captured = <String, Object?>{};
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured['path'] = options.path;
          captured['idempotencyKey'] = options.headers['Idempotency-Key'];
          captured['data'] = options.data;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'success': true,
                'data': {
                  'remoteRecordId': 'cloud-r1',
                  'syncedAt': '2026-05-07T10:00:00Z',
                },
              },
            ),
          );
        },
      ),
    );
    final client = DioCloudRecordClient(dio: dio);
    final record = _record(id: 'r1').copyWith(
      manualReview: ManualReview(
        acceptedRecognitionResult: false,
        manualGrade: RockGrade.iv,
        selectedSupportPlan: const SupportPlan(
          grade: RockGrade.iv,
          methods: [],
          summary: '人工 IV 类支护',
        ),
        reviewerName: '王工',
        note: '人工复核调整',
        reviewedAt: DateTime.utc(2026, 5, 7, 9, 30),
      ),
    );

    final result = await client.syncRecord(
      record,
      idempotencyKey: 'r1_2026-05-07T09:30:00.000Z',
    );

    final capturedData = captured['data'];
    if (capturedData is! Map<String, dynamic>) {
      fail('expected request data to be a JSON map');
    }
    final data = capturedData;
    expect(captured['path'], equals('/api/v1/records/sync'));
    expect(
      captured['idempotencyKey'],
      equals('r1_2026-05-07T09:30:00.000Z'),
    );
    expect(data['id'], equals('r1'));
    expect(data['manualReview'], isA<Map<String, dynamic>>());
    expect(
      (data['manualReview'] as Map<String, dynamic>)['manualGrade'],
      equals('IV'),
    );
    expect(result.remoteRecordId, equals('cloud-r1'));
  });

  test('downloadRecords 从 records 下载云端记录并还原本地模型', () async {
    final source = _record(id: 'r2').copyWith(
      syncStatus: SyncStatus.uploaded,
      remoteRecordId: 'cloud-r2',
      manualReview: ManualReview(
        acceptedRecognitionResult: true,
        reviewerName: '张三',
        reviewedAt: DateTime.utc(2026, 5, 7, 10),
      ),
    );
    final clientForCodec = DioCloudRecordClient(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000')),
    );
    final payload = clientForCodec.encodeRecordForSync(source);
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'success': true,
                'data': {
                  'records': [
                    {
                      'remoteRecordId': 'cloud-r2',
                      'syncedAt': '2026-05-07T10:01:00Z',
                      'record': payload,
                    },
                  ],
                },
              },
            ),
          );
        },
      ),
    );
    final client = DioCloudRecordClient(dio: dio);

    final snapshots = await client.downloadRecords();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.remoteRecordId, equals('cloud-r2'));
    expect(snapshots.single.record.id, equals('r2'));
    expect(snapshots.single.record.manualReview, isNotNull);
    expect(
      snapshots.single.record.manualReview!.acceptedRecognitionResult,
      isTrue,
    );
  });

  test('encodeRecordForSync 单图记录不重复声明第二图资产', () {
    final client = DioCloudRecordClient(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000')),
    );

    final payload = client.encodeRecordForSync(_record(id: 'single'));
    final assets = payload['assets'] as List<dynamic>;
    final kinds = assets
        .cast<Map<String, dynamic>>()
        .map((asset) => asset['kind'])
        .toSet();

    expect(kinds, containsAll(['originalImage1', 'resultImage1']));
    expect(kinds, isNot(contains('originalImage2')));
    expect(kinds, isNot(contains('resultImage2')));
  });

  test('encodeRecordForSync 旧双图记录保留第二图资产', () {
    final client = DioCloudRecordClient(
      dio: Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000')),
    );

    final payload = client.encodeRecordForSync(
      _record(id: 'legacy').copyWith(image2Path: '/tmp/b.jpg'),
    );
    final assets = payload['assets'] as List<dynamic>;
    final kinds = assets
        .cast<Map<String, dynamic>>()
        .map((asset) => asset['kind'])
        .toSet();

    expect(
      kinds,
      containsAll([
        'originalImage1',
        'resultImage1',
        'originalImage2',
        'resultImage2',
      ]),
    );
  });

  test('syncRecord 先上传图片和报告资产，再同步瘦身记录 JSON', () async {
    final tempDir = await Directory.systemTemp.createTemp('crack-sync-test-');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDir.path}/face.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final reportFile = File('${tempDir.path}/report.txt')
      ..writeAsStringSync('report body');
    final captured = <String, Object?>{};
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:8000'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured['data'] = options.data;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: {
                'success': true,
                'data': {'remoteRecordId': 'cloud-r-assets'},
              },
            ),
          );
        },
      ),
    );
    final assetClient = _FakeAssetUploadClient();
    final client = DioCloudRecordClient(
      dio: dio,
      assetUploadClient: assetClient,
    );

    await client.syncRecord(
      _record(id: 'r-assets').copyWith(
        image1Path: imageFile.path,
        image2Path: imageFile.path,
        reportPath: reportFile.path,
      ),
      idempotencyKey: 'r-assets-v1',
    );

    expect(assetClient.requestedKinds, [
      'originalImage1',
      'resultImage1',
      'report',
    ]);
    expect(assetClient.uploadedKinds, [
      'originalImage1',
      'resultImage1',
      'report',
    ]);
    expect(assetClient.lastMetadata?['timestamp'], contains('2026-05-07'));
    final uploadEngineering =
        assetClient.lastMetadata?['engineeringInfo'] as Map<String, dynamic>?;
    expect(uploadEngineering?['workerName'], equals('张三'));
    expect(uploadEngineering?['projectLocation'], equals('二矿598'));
    expect(uploadEngineering?['projectName'], equals('水泵房'));
    final capturedData = captured['data'];
    if (capturedData is! Map<String, dynamic>) {
      fail('expected request data to be a JSON map');
    }
    final data = capturedData;
    expect(data.containsKey('resultImage1'), isFalse);
    expect(data.containsKey('resultImage2'), isFalse);
    final extractedParams = data['extractedParams'] as Map<String, dynamic>;
    expect(extractedParams.containsKey('resultImage1'), isFalse);
    expect(extractedParams.containsKey('resultImage2'), isFalse);
    final assets = (data['assets'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(assets.map((asset) => asset['objectKey']), [
      'records/r-assets/originalImage1/face.jpg',
      'records/r-assets/resultImage1/r-assets_result.png',
      'records/r-assets/report/report.txt',
    ]);
  });
}

JciDetectionResult _record({required String id}) {
  final bytes = Uint8List.fromList([1, 2, 3]);
  return JciDetectionResult(
    id: id,
    timestamp: DateTime.utc(2026, 5, 7, 9),
    image1Path: '/tmp/a.jpg',
    image2Path: '/tmp/a.jpg',
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
      location: '二矿598',
      projectName: '水泵房',
      inspector: '张三',
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
      summary: '算法匹配 II-1 支护',
    ),
    syncStatus: SyncStatus.pendingUpload,
    updatedAt: DateTime.utc(2026, 5, 7, 9, 30),
  );
}

class _FakeAssetUploadClient implements AssetUploadClient {
  final requestedKinds = <String>[];
  final uploadedKinds = <String>[];
  Map<String, dynamic>? lastMetadata;

  @override
  Future<List<PresignedAssetUpload>> requestUploadTargets({
    required String recordId,
    required List<AssetUploadIntent> assets,
    Map<String, dynamic>? metadata,
  }) async {
    lastMetadata = metadata;
    requestedKinds.addAll(assets.map((asset) => asset.kind));
    return [
      for (final asset in assets)
        PresignedAssetUpload(
          kind: asset.kind,
          bucket: 'crack-record-assets',
          objectKey: 'records/$recordId/${asset.kind}/${asset.fileName}',
          uploadUrl: 'http://upload/${asset.kind}',
          downloadUrl: 'http://download/${asset.kind}',
          headers: {'Content-Type': asset.contentType},
        ),
    ];
  }

  @override
  Future<void> uploadBytes({
    required PresignedAssetUpload target,
    required List<int> bytes,
  }) async {
    uploadedKinds.add(target.kind);
  }
}
