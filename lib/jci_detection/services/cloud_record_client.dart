/// 云端 JCI 记录同步客户端
library;

import 'dart:io';

import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/services/asset_upload_client.dart';
import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';
import 'package:crack_app/jci_detection/services/jci_formula_snapshot_service.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';
import 'package:crack_app/jci_detection/services/sync_queue_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 通过 Dio 调用服务器记录同步 API。
class DioCloudRecordClient
    implements CloudRecordClient, CloudRecordDownloadClient {
  /// 创建云端记录客户端
  DioCloudRecordClient({
    required Dio dio,
    AssetUploadClient? assetUploadClient,
    JciStorageService? recordCodec,
    this.syncEndpoint = '/api/v1/records/sync',
    this.recordsEndpoint = '/api/v1/records',
  }) : _dio = dio,
       _assetUploadClient = assetUploadClient,
       _recordCodec = recordCodec ?? JciStorageService();

  final Dio _dio;
  final AssetUploadClient? _assetUploadClient;
  final JciStorageService _recordCodec;

  /// 上传接口路径
  final String syncEndpoint;

  /// 下载接口路径
  final String recordsEndpoint;

  @override
  Future<CloudSyncResult> syncRecord(
    JciDetectionResult record, {
    required String idempotencyKey,
  }) async {
    try {
      final uploadedAssets = await _uploadAssets(record);
      final response = await _dio.post<Map<String, dynamic>>(
        syncEndpoint,
        data: encodeRecordForSync(record, uploadedAssets: uploadedAssets),
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      final data = _unwrapData(response.data);
      final remoteRecordId = data['remoteRecordId'] as String?;
      if (remoteRecordId == null || remoteRecordId.isEmpty) {
        throw const FormatException('同步响应缺少 remoteRecordId');
      }
      return CloudSyncResult(remoteRecordId: remoteRecordId);
    } on DioException catch (error) {
      throw StateError(_cloudErrorMessage(error));
    }
  }

  @override
  Future<List<CloudRecordSnapshot>> downloadRecords() async {
    final response = await _dio.get<Map<String, dynamic>>(recordsEndpoint);
    final data = _unwrapData(response.data);
    final records = data['records'] as List<dynamic>? ?? const [];
    return records
        .map((entry) => _snapshotFromJson(entry as Map<String, dynamic>))
        .toList();
  }

  /// 将记录编码为同步请求体。
  Map<String, dynamic> encodeRecordForSync(
    JciDetectionResult record, {
    List<Map<String, dynamic>>? uploadedAssets,
  }) {
    final json = uploadedAssets == null
        ? _recordCodec.resultToJson(record)
        : _slimRecordJson(record);
    json['assets'] = uploadedAssets ?? _assetReferences(record);
    final formulaSnapshot = _formulaSnapshot(record);
    if (formulaSnapshot != null) {
      json['formulaSnapshot'] = formulaSnapshot;
    }
    return json;
  }

  Future<List<Map<String, dynamic>>> _uploadAssets(
    JciDetectionResult record,
  ) async {
    final client = _assetUploadClient;
    if (client == null) {
      return _assetReferences(record);
    }
    final candidates = await _assetCandidates(record);
    if (candidates.isEmpty) {
      return const [];
    }
    final intents = [
      for (final candidate in candidates)
        AssetUploadIntent(
          kind: candidate.kind,
          fileName: candidate.fileName,
          contentType: candidate.contentType,
          sha256: sha256.convert(candidate.bytes).toString(),
          sizeBytes: candidate.bytes.length,
        ),
    ];
    final targets = await client.requestUploadTargets(
      recordId: record.id,
      assets: intents,
      metadata: _assetUploadMetadata(record),
    );
    final uploaded = <Map<String, dynamic>>[];
    for (final target in targets) {
      final candidate = candidates.firstWhere(
        (item) => item.kind == target.kind,
      );
      await client.uploadBytes(target: target, bytes: candidate.bytes);
      uploaded.add({
        'kind': target.kind,
        'bucket': target.bucket,
        'objectKey': target.objectKey,
        'downloadUrl': target.downloadUrl,
        'contentType': candidate.contentType,
        'sizeBytes': candidate.bytes.length,
        'sha256': sha256.convert(candidate.bytes).toString(),
      });
    }
    return uploaded;
  }

  Future<List<_AssetCandidate>> _assetCandidates(
    JciDetectionResult record,
  ) async {
    final candidates = <_AssetCandidate>[];
    final imageFile = File(record.image1Path);
    if (imageFile.existsSync()) {
      candidates.add(
        _AssetCandidate(
          kind: 'originalImage1',
          fileName: _fileName(record.image1Path, fallback: '${record.id}.jpg'),
          contentType: 'image/jpeg',
          bytes: await imageFile.readAsBytes(),
        ),
      );
    }
    candidates.add(
      _AssetCandidate(
        kind: 'resultImage1',
        fileName: '${record.id}_result.png',
        contentType: 'image/png',
        bytes: record.resultImage1,
      ),
    );
    final hasLegacySecondImage = record.image2Path != record.image1Path;
    if (hasLegacySecondImage) {
      final secondImageFile = File(record.image2Path);
      if (secondImageFile.existsSync()) {
        candidates.add(
          _AssetCandidate(
            kind: 'originalImage2',
            fileName: _fileName(
              record.image2Path,
              fallback: '${record.id}_2.jpg',
            ),
            contentType: 'image/jpeg',
            bytes: await secondImageFile.readAsBytes(),
          ),
        );
      }
      candidates.add(
        _AssetCandidate(
          kind: 'resultImage2',
          fileName: '${record.id}_result_2.png',
          contentType: 'image/png',
          bytes: record.resultImage2,
        ),
      );
    }
    final reportPath = record.reportPath;
    if (reportPath != null) {
      final reportFile = File(reportPath);
      if (reportFile.existsSync()) {
        candidates.add(
          _AssetCandidate(
            kind: 'report',
            fileName: _fileName(
              reportPath,
              fallback: '${record.id}_report.txt',
            ),
            contentType: 'text/plain',
            bytes: await reportFile.readAsBytes(),
          ),
        );
      }
    }
    return candidates;
  }

  Map<String, dynamic> _assetUploadMetadata(JciDetectionResult record) {
    final engineering = record.engineeringInfo;
    return {
      'timestamp': record.timestamp.toUtc().toIso8601String(),
      'operatorUserId': record.operatorUserId,
      'engineeringInfo': {
        'workerName': engineering.workerName,
        'projectLocation': engineering.projectLocation,
        'projectName': engineering.projectName,
      },
    };
  }

  Map<String, dynamic> _slimRecordJson(JciDetectionResult record) {
    final json = _recordCodec.resultToJson(record)
      ..remove('resultImage1')
      ..remove('resultImage2')
      ..remove('reportPath');
    final params = json['extractedParams'];
    if (params is Map<String, dynamic>) {
      params
        ..remove('resultImage1')
        ..remove('resultImage2');
    }
    return json;
  }

  List<Map<String, dynamic>> _assetReferences(JciDetectionResult record) {
    final hasLegacySecondImage = record.image2Path != record.image1Path;
    return [
      {
        'kind': 'originalImage1',
        'localPath': record.image1Path,
      },
      {
        'kind': 'resultImage1',
        'contentType': 'image/png',
        'sizeBytes': record.resultImage1.length,
      },
      if (hasLegacySecondImage) ...[
        {
          'kind': 'originalImage2',
          'localPath': record.image2Path,
        },
        {
          'kind': 'resultImage2',
          'contentType': 'image/png',
          'sizeBytes': record.resultImage2.length,
        },
      ],
      if (record.reportPath != null)
        {
          'kind': 'report',
          'localPath': record.reportPath,
          'contentType': 'text/plain',
        },
    ];
  }

  Map<String, dynamic>? _formulaSnapshot(JciDetectionResult record) {
    final scanline = record.scanlineResult;
    if (scanline == null) {
      return null;
    }
    final indicators = scanline.indicators;
    return JciFormulaSnapshotService().canonicalSnapshot(
      JciInputParameters(
        indicator1: indicators.indicator1,
        indicator2: indicators.indicator2,
        indicator3: indicators.indicator3,
        depth: record.engineeringInfo.elevation,
        ucsMpa: record.engineeringInfo.rockType.ucsMpa,
      ),
    );
  }

  CloudRecordSnapshot _snapshotFromJson(Map<String, dynamic> json) {
    final recordJson = json['record'] as Map<String, dynamic>? ?? json;
    final record = _recordCodec.resultFromJson(recordJson);
    final remoteRecordId =
        json['remoteRecordId'] as String? ?? record.remoteRecordId ?? record.id;
    final syncedAtString = json['syncedAt'] as String?;
    return CloudRecordSnapshot(
      remoteRecordId: remoteRecordId,
      record: record.copyWith(remoteRecordId: remoteRecordId),
      syncedAt: syncedAtString == null
          ? DateTime.now()
          : DateTime.parse(syncedAtString),
    );
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic>? body) {
    if (body == null) {
      throw const FormatException('服务器响应为空');
    }
    final success = body['success'];
    if (success == false) {
      final message = body['message'] as String? ?? '云端同步失败';
      throw StateError(message);
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return body;
  }

  String _cloudErrorMessage(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final message = body['message'] as String?;
      final requestId = body['requestId'] as String?;
      final detail = body['detail'] as String?;
      final base = message == null || message.isEmpty ? '服务器同步失败' : message;
      return [
        base,
        if (requestId != null && requestId.isNotEmpty) 'requestId=$requestId',
        if (detail != null && detail.isNotEmpty) detail,
      ].join('，');
    }
    if (error.response?.statusCode != null) {
      return '服务器同步失败，HTTP ${error.response!.statusCode}';
    }
    return '服务器同步失败: ${error.message ?? error.type.name}';
  }

  String _fileName(String path, {required String fallback}) {
    final normalized = path.replaceAll(r'\', '/');
    final value = normalized.split('/').last.trim();
    return value.isEmpty ? fallback : value;
  }
}

class _AssetCandidate {
  const _AssetCandidate({
    required this.kind,
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final String kind;
  final String fileName;
  final String contentType;
  final List<int> bytes;
}
