/// 在线/离线推理路由
library;

import 'package:crack_app/core/network/network_status_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';

/// 根据推理模式、网络健康状态和服务器失败情况选择推理路径。
class InferenceRouter {
  /// 创建推理路由
  const InferenceRouter({
    required InferenceClient localClient,
    required InferenceClient remoteClient,
    required NetworkStatusService networkStatusService,
  }) : _localClient = localClient,
       _remoteClient = remoteClient,
       _networkStatusService = networkStatusService;

  final InferenceClient _localClient;
  final InferenceClient _remoteClient;
  final NetworkStatusService _networkStatusService;

  /// 执行推理
  Future<RoutedInferenceResult> detect(InferenceRequest request) async {
    switch (request.mode) {
      case InferenceMode.offlineOnly:
        return _detectOffline(request);
      case InferenceMode.onlineOnly:
        return _detectOnlineOnly(request);
      case InferenceMode.auto:
        return _detectAuto(request);
    }
  }

  Future<RoutedInferenceResult> _detectAuto(InferenceRequest request) async {
    final reachable = await _networkStatusService.canReachServer();
    if (!reachable) {
      return _detectOffline(request);
    }

    try {
      final detection = await _remoteClient.detect(request);
      return RoutedInferenceResult(
        detection: detection,
        source: InferenceSource.online,
      );
    } on Object catch (error) {
      final fallback = await _localClient.detect(request);
      return RoutedInferenceResult(
        detection: fallback,
        source: InferenceSource.onlineFailedOfflineFallback,
        fallbackReason: error.toString(),
      );
    }
  }

  Future<RoutedInferenceResult> _detectOnlineOnly(
    InferenceRequest request,
  ) async {
    try {
      final detection = await _remoteClient.detect(request);
      return RoutedInferenceResult(
        detection: detection,
        source: InferenceSource.online,
      );
    } on Object catch (error) {
      throw InferenceException('服务器推理失败', error);
    }
  }

  Future<RoutedInferenceResult> _detectOffline(InferenceRequest request) async {
    final detection = await _localClient.detect(request);
    return RoutedInferenceResult(
      detection: detection,
      source: InferenceSource.offline,
    );
  }
}
