/// 记录图片/报告对象存储上传客户端
library;

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

/// 待上传资源描述。
class AssetUploadIntent extends Equatable {
  /// 创建上传意图。
  const AssetUploadIntent({
    required this.kind,
    required this.fileName,
    required this.contentType,
    this.sha256,
    this.sizeBytes,
  });

  /// 资源类型，例如 originalImage/resultImage/mask/report。
  final String kind;

  /// 文件名。
  final String fileName;

  /// MIME 类型。
  final String contentType;

  /// 文件 sha256。
  final String? sha256;

  /// 文件大小。
  final int? sizeBytes;

  /// JSON。
  Map<String, dynamic> toJson() {
    return {
      'kind': kind,
      'fileName': fileName,
      'contentType': contentType,
      'sha256': sha256,
      'sizeBytes': sizeBytes,
    };
  }

  @override
  List<Object?> get props => [kind, fileName, contentType, sha256, sizeBytes];
}

/// 服务器返回的预签名上传目标。
class PresignedAssetUpload extends Equatable {
  /// 创建预签名上传目标。
  const PresignedAssetUpload({
    required this.kind,
    required this.bucket,
    required this.objectKey,
    required this.uploadUrl,
    required this.downloadUrl,
    required this.headers,
  });

  /// JSON 转模型。
  factory PresignedAssetUpload.fromJson(Map<String, dynamic> json) {
    return PresignedAssetUpload(
      kind: json['kind'] as String? ?? '',
      bucket: json['bucket'] as String? ?? '',
      objectKey: json['objectKey'] as String? ?? '',
      uploadUrl: json['uploadUrl'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      headers: (json['headers'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }

  /// 资源类型。
  final String kind;

  /// bucket。
  final String bucket;

  /// object key。
  final String objectKey;

  /// PUT 上传 URL。
  final String uploadUrl;

  /// 下载 URL。
  final String downloadUrl;

  /// 上传需要携带的 headers。
  final Map<String, String> headers;

  @override
  List<Object?> get props => [
    kind,
    bucket,
    objectKey,
    uploadUrl,
    downloadUrl,
    headers,
  ];
}

/// 资产上传客户端边界。
abstract interface class AssetUploadClient {
  /// 获取预签名上传目标。
  Future<List<PresignedAssetUpload>> requestUploadTargets({
    required String recordId,
    required List<AssetUploadIntent> assets,
    Map<String, dynamic>? metadata,
  });

  /// 上传字节到预签名目标。
  Future<void> uploadBytes({
    required PresignedAssetUpload target,
    required List<int> bytes,
  });
}

/// Dio 实现。
class DioAssetUploadClient implements AssetUploadClient {
  /// 创建 Dio 上传客户端。
  const DioAssetUploadClient({
    required Dio dio,
    Dio? uploadDio,
    this.presignEndpoint = '/api/v1/uploads/presign',
  }) : _dio = dio,
       _uploadDio = uploadDio;

  final Dio _dio;
  final Dio? _uploadDio;

  /// presign 接口。
  final String presignEndpoint;

  @override
  Future<List<PresignedAssetUpload>> requestUploadTargets({
    required String recordId,
    required List<AssetUploadIntent> assets,
    Map<String, dynamic>? metadata,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      presignEndpoint,
      data: {
        'recordId': recordId,
        'assets': assets.map((asset) => asset.toJson()).toList(),
        ...?(metadata == null ? null : {'metadata': metadata}),
      },
    );
    final data = _unwrapData(response.data);
    final uploads = data['uploads'] as List<dynamic>? ?? const [];
    return uploads
        .map(
          (item) => PresignedAssetUpload.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> uploadBytes({
    required PresignedAssetUpload target,
    required List<int> bytes,
  }) async {
    final dio =
        _uploadDio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 60),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
    await dio.putUri<void>(
      Uri.parse(target.uploadUrl),
      data: bytes,
      options: Options(
        headers: target.headers,
        contentType: target.headers['Content-Type'],
      ),
    );
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic>? body) {
    if (body == null) {
      throw const FormatException('服务器响应为空');
    }
    if (body['success'] == false) {
      throw StateError(body['message'] as String? ?? '请求上传地址失败');
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return data;
    }
    return body;
  }
}
