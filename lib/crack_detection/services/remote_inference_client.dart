/// 服务器裂隙推理客户端
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';
import 'package:dio/dio.dart';

/// 调用服务器 `POST /inference/crack` 的远程推理客户端。
class RemoteInferenceClient implements InferenceClient {
  /// 创建远程推理客户端
  const RemoteInferenceClient({
    required Dio dio,
    this.endpoint = '/inference/crack',
  }) : _dio = dio;

  final Dio _dio;

  /// 推理接口路径
  final String endpoint;

  @override
  Future<CrackDetectionResult> detect(InferenceRequest request) async {
    final formData = FormData.fromMap({
      'threshold': request.threshold,
      'maxWindows': request.maxWindows,
      'image': await MultipartFile.fromFile(
        request.imagePath,
        filename: request.imagePath.split(Platform.pathSeparator).last,
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      endpoint,
      data: formData,
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 10),
      ),
    );
    final body = response.data;
    if (body == null) {
      throw const InferenceException('服务器响应为空');
    }

    final data = (body['data'] as Map<String, dynamic>?) ?? body;
    return CrackDetectionResult(
      crackRatio: (data['crackRatio'] as num).toDouble(),
      inferenceTime: (data['inferenceTime'] as num?)?.toInt() ?? 0,
      resultImage: _decodeImageBytes(data['resultImage']),
      detectionCount: (data['detectionCount'] as num?)?.toInt() ?? 1,
      binaryMask: _decodeMask(data['binaryMask']),
      originalWidth: (data['originalWidth'] as num?)?.toInt() ?? 0,
      originalHeight: (data['originalHeight'] as num?)?.toInt() ?? 0,
      modelVersion: data['modelVersion'] as String?,
      serverVersion: data['serverVersion'] as String?,
    );
  }

  Uint8List _decodeImageBytes(Object? value) {
    if (value is String && value.isNotEmpty) {
      return base64Decode(value);
    }
    return Uint8List(0);
  }

  List<List<bool>>? _decodeMask(Object? value) {
    if (value is! List) {
      return null;
    }
    return value
        .map(
          (row) => (row as List)
              .map((pixel) => pixel == true || pixel == 1)
              .toList(),
        )
        .toList();
  }
}
