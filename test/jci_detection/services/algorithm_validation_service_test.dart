import 'package:crack_app/jci_detection/services/algorithm_validation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AlgorithmValidationService service;

  setUp(() {
    service = const AlgorithmValidationService();
  });

  List<List<bool>> emptyMask(int width, int height) {
    return List.generate(height, (_) => List.filled(width, false));
  }

  test('从真实二值 mask 计算连通裂隙、25cm 过滤和三大指标', () {
    final mask = emptyMask(100, 100);

    for (var x = 0; x < 50; x++) {
      mask[33][x] = true;
    }
    for (var x = 70; x < 100; x++) {
      mask[33][x] = true;
    }
    for (var y = 0; y < 50; y++) {
      mask[y][66] = true;
    }

    final result = service.analyzeMask(
      crackMask: mask,
      pixelRatio: 1,
      imageWidth: 100,
      imageHeight: 100,
    );

    expect(result.crackResult.cracks.length, equals(3));
    expect(result.indicators.totalCracks, equals(3));
    expect(result.indicators.cracksAbove25cm, equals(2));
    expect(result.indicators.imageAreaM2, closeTo(1, 1e-9));
    expect(result.indicators.indicator1, closeTo(2, 1e-9));
    expect(result.indicators.indicator2, closeTo(20 / 3, 1e-9));
    expect(result.indicators.indicator3, closeTo(0.65, 1e-9));
    expect(result.crackRatio, closeTo(1.3, 1e-9));
  });

  test('加粗对角裂隙应作为单条连通裂隙参与验证', () {
    final mask = emptyMask(80, 80);

    for (var i = 0; i < 35; i++) {
      final x = 10 + i;
      final y = 10 + i;
      mask[y][x] = true;
      if (i < 34) {
        mask[y + 1][x] = true;
      }
    }

    final result = service.analyzeMask(
      crackMask: mask,
      pixelRatio: 1,
      imageWidth: 80,
      imageHeight: 80,
    );

    expect(result.crackResult.cracks.length, equals(1));
    expect(result.indicators.totalCracks, equals(1));
    expect(result.indicators.totalCrackLength, greaterThan(25));
  });

  test('线上和离线相同 mask 的一致性验证应通过', () {
    final mask = emptyMask(40, 40);
    for (var x = 5; x < 25; x++) {
      mask[13][x] = true;
    }

    final local = service.analyzeMask(
      crackMask: mask,
      pixelRatio: 1,
      imageWidth: 40,
      imageHeight: 40,
    );
    final remote = service.analyzeMask(
      crackMask: mask,
      pixelRatio: 1,
      imageWidth: 40,
      imageHeight: 40,
    );

    final comparison = service.compare(
      local: local,
      remote: remote,
      localMask: mask,
      remoteMask: mask,
    );

    expect(comparison.maskIou, closeTo(1, 1e-9));
    expect(comparison.isWithinTolerance, isTrue);
    expect(comparison.failedReasons, isEmpty);
  });
}
