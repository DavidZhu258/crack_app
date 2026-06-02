import 'dart:async';
import 'dart:typed_data';

import 'package:crack_app/crack_detection/cubit/crack_detection_cubit.dart';
import 'package:crack_app/crack_detection/cubit/crack_detection_state.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockCrackDetectionService extends Mock implements CrackDetectionService {}

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  late MockCrackDetectionService service;
  late MockImagePicker imagePicker;

  final successResult = CrackDetectionResult(
    crackRatio: 1.2,
    inferenceTime: 100,
    resultImage: Uint8List.fromList([1, 2, 3]),
    detectionCount: 1,
  );

  setUp(() {
    service = MockCrackDetectionService();
    imagePicker = MockImagePicker();
    when(() => service.isModelLoaded).thenReturn(true);
  });

  test('默认窗口数量使用交互测试安全值，避免测试图片检测长时间无响应', () async {
    final cubit = CrackDetectionCubit(
      service: service,
      imagePicker: imagePicker,
    );

    expect(cubit.maxWindows, equals(4));

    await cubit.close();
  });

  test('测试图片检测在调用原生推理前先让 UI 绘制检测中状态', () async {
    final frameGate = Completer<void>();
    final detectionGate = Completer<CrackDetectionResult>();
    when(
      () => service.loadTestImageFromAssets('assets/images/test/14.jpg'),
    ).thenAnswer((_) async => '/tmp/14.jpg');
    when(
      () => service.detectCrack(
        '/tmp/14.jpg',
        maxWindows: 4,
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) => detectionGate.future);

    final cubit = CrackDetectionCubit(
      service: service,
      imagePicker: imagePicker,
      waitForUiFrameBeforeDetection: () => frameGate.future,
    );

    final task = cubit.detectWithTestImage('assets/images/test/14.jpg');
    await Future<void>.delayed(Duration.zero);

    final inProgress = cubit.state as CrackDetectionInProgress;
    expect(inProgress.imagePath, equals('/tmp/14.jpg'));
    expect(inProgress.statusText, equals('正在准备离线识别界面...'));
    verifyNever(
      () => service.detectCrack(
        any(),
        maxWindows: any(named: 'maxWindows'),
        onProgress: any(named: 'onProgress'),
      ),
    );

    frameGate.complete();
    await Future<void>.delayed(Duration.zero);

    verify(
      () => service.detectCrack(
        '/tmp/14.jpg',
        maxWindows: 4,
        onProgress: any(named: 'onProgress'),
      ),
    ).called(1);

    detectionGate.complete(successResult);
    await task;

    expect(cubit.state, isA<CrackDetectionSuccess>());

    await cubit.close();
  });

  test('离线检测等待状态明确说明端侧识别进度', () async {
    final frameGate = Completer<void>();
    final detectionGate = Completer<CrackDetectionResult>();
    when(
      () => service.loadTestImageFromAssets('assets/images/test/14.jpg'),
    ).thenAnswer((_) async => '/tmp/14.jpg');
    when(
      () => service.detectCrack(
        '/tmp/14.jpg',
        maxWindows: 4,
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) => detectionGate.future);

    final cubit = CrackDetectionCubit(
      service: service,
      imagePicker: imagePicker,
      waitForUiFrameBeforeDetection: () => frameGate.future,
    );

    final task = cubit.detectWithTestImage('assets/images/test/14.jpg');
    await Future<void>.delayed(Duration.zero);
    expect(
      (cubit.state as CrackDetectionInProgress).statusText,
      equals('正在准备离线识别界面...'),
    );

    frameGate.complete();
    await Future<void>.delayed(Duration.zero);

    final progressCallback =
        verify(
              () => service.detectCrack(
                '/tmp/14.jpg',
                maxWindows: 4,
                onProgress: captureAny(named: 'onProgress'),
              ),
            ).captured.single
            as void Function(int, int, String);
    progressCallback(1, 4, '推理中 1/4');

    final inProgress = cubit.state as CrackDetectionInProgress;
    expect(inProgress.currentWindow, equals(1));
    expect(inProgress.totalWindows, equals(4));
    expect(
      inProgress.statusText,
      equals('正在进行端侧离线识别：推理中 1/4'),
    );

    detectionGate.complete(successResult);
    await task;
    expect(cubit.state, isA<CrackDetectionSuccess>());

    await cubit.close();
  });
}
