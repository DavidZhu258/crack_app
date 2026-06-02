import 'dart:math';
import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/jci_detection/services/image_analyzer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCrackDetectionService extends Mock implements CrackDetectionService {}

void main() {
  late MockCrackDetectionService mockCrackService;
  late ImageAnalyzerService service;

  setUp(() {
    mockCrackService = MockCrackDetectionService();
    service = ImageAnalyzerService(crackService: mockCrackService);
  });

  group('ImageAnalyzerService - Property 10: 参数提取范围有效性', () {
    // Feature: jci-calculation, Property 10: 参数提取范围有效性
    // **Validates: Requirements 2.2-2.4**
    //
    // 对于任意裂缝检测结果，提取的参数应满足：
    // - RQD 值在 0-100 范围内
    // - 节理间距为非负数
    // - 节理面密度为非负数

    /// 生成随机 CrackDetectionResult
    CrackDetectionResult generateResult(Random random) {
      // crackRatio 范围: 0 到 100（百分比）
      final crackRatio = random.nextDouble() * 100;
      return CrackDetectionResult(
        crackRatio: crackRatio,
        inferenceTime: random.nextInt(1000),
        resultImage: Uint8List.fromList([1, 2, 3]),
        detectionCount: random.nextInt(50),
      );
    }

    test('属性测试: RQD 值在 0-100 范围内 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final result = generateResult(random);
        final rqd = service.extractRqd(result);

        expect(
          rqd,
          greaterThanOrEqualTo(0),
          reason:
              'crackRatio=${result.crackRatio}: '
              'RQD=$rqd 应 >= 0',
        );
        expect(
          rqd,
          lessThanOrEqualTo(100),
          reason:
              'crackRatio=${result.crackRatio}: '
              'RQD=$rqd 应 <= 100',
        );
      }
    });

    test('属性测试: 节理间距为非负数 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final result = generateResult(random);
        final spacing = service.calculateJointSpacing(result);

        expect(
          spacing,
          greaterThanOrEqualTo(0),
          reason:
              'crackRatio=${result.crackRatio}: '
              '节理间距=$spacing 应 >= 0',
        );
      }
    });

    test('属性测试: 节理面密度为非负数 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final result = generateResult(random);
        final density = service.calculateJointDensity(result);

        expect(
          density,
          greaterThanOrEqualTo(0),
          reason:
              'crackRatio=${result.crackRatio}: '
              '节理面密度=$density 应 >= 0',
        );
      }
    });

    test('属性测试: 极端 crackRatio 值的参数范围有效性', () {
      final extremeRatios = [0.0, 0.001, 50.0, 79.9, 80.0, 100.0];

      for (final ratio in extremeRatios) {
        final result = CrackDetectionResult(
          crackRatio: ratio,
          inferenceTime: 100,
          resultImage: Uint8List.fromList([1, 2, 3]),
          detectionCount: 1,
        );

        final rqd = service.extractRqd(result);
        final spacing = service.calculateJointSpacing(result);
        final density = service.calculateJointDensity(result);

        expect(
          rqd,
          greaterThanOrEqualTo(0),
          reason: 'crackRatio=$ratio: RQD=$rqd 应 >= 0',
        );
        expect(
          rqd,
          lessThanOrEqualTo(100),
          reason: 'crackRatio=$ratio: RQD=$rqd 应 <= 100',
        );
        expect(
          spacing,
          greaterThanOrEqualTo(0),
          reason: 'crackRatio=$ratio: 节理间距=$spacing 应 >= 0',
        );
        expect(
          density,
          greaterThanOrEqualTo(0),
          reason: 'crackRatio=$ratio: 节理面密度=$density 应 >= 0',
        );
      }
    });

    test('属性测试: 所有三个参数同时满足范围约束 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final result = generateResult(random);
        final rqd = service.extractRqd(result);
        final spacing = service.calculateJointSpacing(result);
        final density = service.calculateJointDensity(result);

        expect(
          rqd >= 0 && rqd <= 100,
          isTrue,
          reason: 'crackRatio=${result.crackRatio}: RQD=$rqd 超出范围',
        );
        expect(
          spacing >= 0,
          isTrue,
          reason: 'crackRatio=${result.crackRatio}: 节理间距=$spacing 为负数',
        );
        expect(
          density >= 0,
          isTrue,
          reason: 'crackRatio=${result.crackRatio}: 节理面密度=$density 为负数',
        );
      }
    });
  });
}
