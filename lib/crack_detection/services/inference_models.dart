/// 线上/离线推理共享模型
library;

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:equatable/equatable.dart';

/// 推理模式
enum InferenceMode {
  /// 自动：优先服务器，可失败回退离线
  auto,

  /// 强制手机端离线推理
  offlineOnly,

  /// 强制服务器推理
  onlineOnly,
}

/// 实际推理来源
enum InferenceSource {
  /// 手机端离线推理
  offline,

  /// 服务器推理
  online,

  /// 服务器失败后回退手机端
  onlineFailedOfflineFallback,
}

/// 推理请求
class InferenceRequest extends Equatable {
  /// 创建推理请求
  const InferenceRequest({
    required this.imagePath,
    this.mode = InferenceMode.auto,
    this.threshold = 0.3,
    this.maxWindows = 20,
  });

  /// 图像路径
  final String imagePath;

  /// 推理模式
  final InferenceMode mode;

  /// 分割阈值
  final double threshold;

  /// 最大滑动窗口数
  final int maxWindows;

  @override
  List<Object?> get props => [imagePath, mode, threshold, maxWindows];
}

/// 推理客户端抽象
// ignore: one_member_abstracts
abstract interface class InferenceClient {
  /// 执行推理，返回统一检测结果
  Future<CrackDetectionResult> detect(InferenceRequest request);
}

/// 推理路由结果
class RoutedInferenceResult extends Equatable {
  /// 创建路由结果
  const RoutedInferenceResult({
    required this.detection,
    required this.source,
    this.fallbackReason,
  });

  /// 检测结果
  final CrackDetectionResult detection;

  /// 实际来源
  final InferenceSource source;

  /// 回退原因
  final String? fallbackReason;

  @override
  List<Object?> get props => [detection, source, fallbackReason];
}

/// 推理异常
class InferenceException implements Exception {
  /// 创建异常
  const InferenceException(this.message, [this.cause]);

  /// 错误说明
  final String message;

  /// 原始异常
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'InferenceException: $message';
    }
    return 'InferenceException: $message ($cause)';
  }
}
