import 'dart:typed_data';

import 'package:crack_app/core/network/network_status_service.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';
import 'package:crack_app/crack_detection/services/inference_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CrackDetectionResult detection(String label) {
    final isOnline = label == 'online';
    return CrackDetectionResult(
      crackRatio: isOnline ? 6 : 5,
      inferenceTime: isOnline ? 20 : 50,
      resultImage: Uint8List.fromList([1, 2, 3]),
      detectionCount: 1,
      binaryMask: [
        [true, false],
        [false, true],
      ],
      originalWidth: 2,
      originalHeight: 2,
      modelVersion: 'test-model',
    );
  }

  test('auto 模式无可用网络时走离线推理', () async {
    final local = _FakeInferenceClient(result: detection('offline'));
    final remote = _FakeInferenceClient(result: detection('online'));
    final router = InferenceRouter(
      localClient: local,
      remoteClient: remote,
      networkStatusService: const _FakeNetworkStatusService(reachable: false),
    );

    final result = await router.detect(
      const InferenceRequest(imagePath: 'a.jpg'),
    );

    expect(result.source, equals(InferenceSource.offline));
    expect(result.detection.crackRatio, equals(5));
    expect(local.calls, equals(1));
    expect(remote.calls, equals(0));
  });

  test('auto 模式健康检查通过时优先走服务器推理', () async {
    final local = _FakeInferenceClient(result: detection('offline'));
    final remote = _FakeInferenceClient(result: detection('online'));
    final router = InferenceRouter(
      localClient: local,
      remoteClient: remote,
      networkStatusService: const _FakeNetworkStatusService(reachable: true),
    );

    final result = await router.detect(
      const InferenceRequest(imagePath: 'a.jpg'),
    );

    expect(result.source, equals(InferenceSource.online));
    expect(result.detection.crackRatio, equals(6));
    expect(local.calls, equals(0));
    expect(remote.calls, equals(1));
  });

  test('auto 模式服务器失败时回退离线且保留失败原因', () async {
    final local = _FakeInferenceClient(result: detection('offline'));
    final remote = _FakeInferenceClient(error: StateError('server down'));
    final router = InferenceRouter(
      localClient: local,
      remoteClient: remote,
      networkStatusService: const _FakeNetworkStatusService(reachable: true),
    );

    final result = await router.detect(
      const InferenceRequest(imagePath: 'a.jpg'),
    );

    expect(result.source, equals(InferenceSource.onlineFailedOfflineFallback));
    expect(result.detection.crackRatio, equals(5));
    expect(result.fallbackReason, contains('server down'));
    expect(local.calls, equals(1));
    expect(remote.calls, equals(1));
  });

  test('onlineOnly 模式服务器失败时抛错且不回退离线', () async {
    final local = _FakeInferenceClient(result: detection('offline'));
    final remote = _FakeInferenceClient(error: StateError('server down'));
    final router = InferenceRouter(
      localClient: local,
      remoteClient: remote,
      networkStatusService: const _FakeNetworkStatusService(reachable: true),
    );

    await expectLater(
      router.detect(
        const InferenceRequest(
          imagePath: 'a.jpg',
          mode: InferenceMode.onlineOnly,
        ),
      ),
      throwsA(isA<InferenceException>()),
    );

    expect(local.calls, equals(0));
    expect(remote.calls, equals(1));
  });

  test('offlineOnly 模式始终走离线推理', () async {
    final local = _FakeInferenceClient(result: detection('offline'));
    final remote = _FakeInferenceClient(result: detection('online'));
    final router = InferenceRouter(
      localClient: local,
      remoteClient: remote,
      networkStatusService: const _FakeNetworkStatusService(reachable: true),
    );

    final result = await router.detect(
      const InferenceRequest(
        imagePath: 'a.jpg',
        mode: InferenceMode.offlineOnly,
      ),
    );

    expect(result.source, equals(InferenceSource.offline));
    expect(local.calls, equals(1));
    expect(remote.calls, equals(0));
  });
}

class _FakeNetworkStatusService implements NetworkStatusService {
  const _FakeNetworkStatusService({required this.reachable});

  final bool reachable;

  @override
  Future<bool> canReachServer() async => reachable;
}

class _FakeInferenceClient implements InferenceClient {
  _FakeInferenceClient({this.result, this.error});

  final CrackDetectionResult? result;
  final Object? error;
  int calls = 0;

  @override
  Future<CrackDetectionResult> detect(InferenceRequest request) async {
    calls++;
    final exception = error;
    if (exception != null) {
      if (exception is Error) {
        throw exception;
      }
      if (exception is Exception) {
        throw exception;
      }
      throw StateError(exception.toString());
    }
    return result!;
  }
}
