/// 手机端离线推理客户端
library;

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';

/// 包装现有 ONNX 裂隙检测服务。
class LocalInferenceClient implements InferenceClient {
  /// 创建本地推理客户端
  const LocalInferenceClient(this._crackDetectionService);

  final CrackDetectionService _crackDetectionService;

  @override
  Future<CrackDetectionResult> detect(InferenceRequest request) {
    return _crackDetectionService.detectCrack(
      request.imagePath,
      threshold: request.threshold,
      maxWindows: request.maxWindows,
    );
  }
}
