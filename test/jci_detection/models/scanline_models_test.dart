import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scanline', () {
    test('应该正确创建实例并存储所有字段', () {
      const scanline = Scanline(
        name: '横线1',
        isHorizontal: true,
        position: 200,
        start: 0,
        end: 600,
      );

      expect(scanline.name, equals('横线1'));
      expect(scanline.isHorizontal, isTrue);
      expect(scanline.position, equals(200));
      expect(scanline.start, equals(0));
      expect(scanline.end, equals(600));
    });

    test('应该支持 Equatable 值相等比较', () {
      const scanline1 = Scanline(
        name: '横线1',
        isHorizontal: true,
        position: 200,
        start: 0,
        end: 600,
      );
      const scanline2 = Scanline(
        name: '横线1',
        isHorizontal: true,
        position: 200,
        start: 0,
        end: 600,
      );
      const scanline3 = Scanline(
        name: '竖线1',
        isHorizontal: false,
        position: 200,
        start: 0,
        end: 600,
      );

      expect(scanline1, equals(scanline2));
      expect(scanline1, isNot(equals(scanline3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = Scanline(
        name: '横线1',
        isHorizontal: true,
        position: 200,
        start: 0,
        end: 600,
      );

      final updated = original.copyWith(name: '横线2', position: 400);

      expect(updated.name, equals('横线2'));
      expect(updated.isHorizontal, isTrue);
      expect(updated.position, equals(400));
      expect(updated.start, equals(0));
      expect(updated.end, equals(600));
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = Scanline(
        name: '竖线1',
        isHorizontal: false,
        position: 300,
        start: 0,
        end: 900,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const scanline = Scanline(
        name: '横线1',
        isHorizontal: true,
        position: 200,
        start: 0,
        end: 600,
      );

      expect(scanline.props, equals(['横线1', true, 200, 0, 600]));
    });
  });

  group('ScanlineIntersection', () {
    test('应该正确创建实例并存储所有字段', () {
      const intersection = ScanlineIntersection(
        label: '交点A',
        pixelX: 150,
        pixelY: 200,
        distanceFromStart: 7.5,
      );

      expect(intersection.label, equals('交点A'));
      expect(intersection.pixelX, equals(150));
      expect(intersection.pixelY, equals(200));
      expect(intersection.distanceFromStart, equals(7.5));
    });

    test('应该支持 Equatable 值相等比较', () {
      const intersection1 = ScanlineIntersection(
        label: '交点A',
        pixelX: 150,
        pixelY: 200,
        distanceFromStart: 7.5,
      );
      const intersection2 = ScanlineIntersection(
        label: '交点A',
        pixelX: 150,
        pixelY: 200,
        distanceFromStart: 7.5,
      );
      const intersection3 = ScanlineIntersection(
        label: '交点B',
        pixelX: 300,
        pixelY: 200,
        distanceFromStart: 15,
      );

      expect(intersection1, equals(intersection2));
      expect(intersection1, isNot(equals(intersection3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = ScanlineIntersection(
        label: '交点A',
        pixelX: 150,
        pixelY: 200,
        distanceFromStart: 7.5,
      );

      final updated = original.copyWith(label: '交点B', pixelX: 300);

      expect(updated.label, equals('交点B'));
      expect(updated.pixelX, equals(300));
      expect(updated.pixelY, equals(200));
      expect(updated.distanceFromStart, equals(7.5));
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = ScanlineIntersection(
        label: '交点A',
        pixelX: 150,
        pixelY: 200,
        distanceFromStart: 7.5,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const intersection = ScanlineIntersection(
        label: '交点A',
        pixelX: 150,
        pixelY: 200,
        distanceFromStart: 7.5,
      );

      expect(intersection.props, equals(['交点A', 150, 200, 7.5]));
    });
  });

  group('ScanlineResult', () {
    const intersections = [
      ScanlineIntersection(
        label: '交点A',
        pixelX: 100,
        pixelY: 200,
        distanceFromStart: 5,
      ),
      ScanlineIntersection(
        label: '交点B',
        pixelX: 300,
        pixelY: 200,
        distanceFromStart: 15,
      ),
    ];

    test('应该正确创建有效测线结果实例', () {
      const result = ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );

      expect(result.name, equals('横线1'));
      expect(result.jointSpacing, equals(5.0));
      expect(result.effectiveLength, equals(10.0));
      expect(result.intersectionCount, equals(2));
      expect(result.intersections, equals(intersections));
      expect(result.isValid, isTrue);
    });

    test('应该支持无交点的无效测线结果', () {
      const result = ScanlineResult(
        name: '竖线2',
        jointSpacing: 0,
        effectiveLength: 0,
        intersectionCount: 0,
        intersections: [],
        isValid: false,
      );

      expect(result.intersectionCount, equals(0));
      expect(result.intersections, isEmpty);
      expect(result.isValid, isFalse);
    });

    test('应该支持 Equatable 值相等比较', () {
      const result1 = ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );
      const result2 = ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );
      const result3 = ScanlineResult(
        name: '横线2',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );

      final updated = original.copyWith(
        name: '横线2',
        jointSpacing: 8,
      );

      expect(updated.name, equals('横线2'));
      expect(updated.jointSpacing, equals(8.0));
      expect(updated.effectiveLength, equals(10.0));
      expect(updated.intersectionCount, equals(2));
      expect(updated.intersections, equals(intersections));
      expect(updated.isValid, isTrue);
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const result = ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: intersections,
        isValid: true,
      );

      expect(
        result.props,
        equals(['横线1', 5.0, 10.0, 2, intersections, true]),
      );
    });
  });

  group('ThreeIndicators', () {
    test('应该正确创建实例并存储所有字段', () {
      const indicators = ThreeIndicators(
        indicator1: 12.5,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 25,
        cracksAbove25cm: 10,
        totalCrackLength: 450,
        imageAreaM2: 0.8,
      );

      expect(indicators.indicator1, equals(12.5));
      expect(indicators.indicator2, equals(8.3));
      expect(indicators.indicator3, equals(2.1));
      expect(indicators.totalCracks, equals(25));
      expect(indicators.cracksAbove25cm, equals(10));
      expect(indicators.totalCrackLength, equals(450.0));
      expect(indicators.imageAreaM2, equals(0.8));
    });

    test('应该支持零值指标（无裂缝情况）', () {
      const indicators = ThreeIndicators(
        indicator1: 0,
        indicator2: 0,
        indicator3: 0,
        totalCracks: 0,
        cracksAbove25cm: 0,
        totalCrackLength: 0,
        imageAreaM2: 1,
      );

      expect(indicators.indicator1, equals(0));
      expect(indicators.totalCracks, equals(0));
      expect(indicators.totalCrackLength, equals(0));
    });

    test('应该支持 Equatable 值相等比较', () {
      const indicators1 = ThreeIndicators(
        indicator1: 12.5,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 25,
        cracksAbove25cm: 10,
        totalCrackLength: 450,
        imageAreaM2: 0.8,
      );
      const indicators2 = ThreeIndicators(
        indicator1: 12.5,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 25,
        cracksAbove25cm: 10,
        totalCrackLength: 450,
        imageAreaM2: 0.8,
      );
      const indicators3 = ThreeIndicators(
        indicator1: 15,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 30,
        cracksAbove25cm: 12,
        totalCrackLength: 500,
        imageAreaM2: 1,
      );

      expect(indicators1, equals(indicators2));
      expect(indicators1, isNot(equals(indicators3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = ThreeIndicators(
        indicator1: 12.5,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 25,
        cracksAbove25cm: 10,
        totalCrackLength: 450,
        imageAreaM2: 0.8,
      );

      final updated = original.copyWith(
        indicator1: 15,
        totalCracks: 30,
      );

      expect(updated.indicator1, equals(15.0));
      expect(updated.indicator2, equals(8.3));
      expect(updated.indicator3, equals(2.1));
      expect(updated.totalCracks, equals(30));
      expect(updated.cracksAbove25cm, equals(10));
      expect(updated.totalCrackLength, equals(450.0));
      expect(updated.imageAreaM2, equals(0.8));
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = ThreeIndicators(
        indicator1: 12.5,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 25,
        cracksAbove25cm: 10,
        totalCrackLength: 450,
        imageAreaM2: 0.8,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const indicators = ThreeIndicators(
        indicator1: 12.5,
        indicator2: 8.3,
        indicator3: 2.1,
        totalCracks: 25,
        cracksAbove25cm: 10,
        totalCrackLength: 450,
        imageAreaM2: 0.8,
      );

      expect(
        indicators.props,
        equals([12.5, 8.3, 2.1, 25, 10, 450.0, 0.8]),
      );
    });
  });

  group('ScanlineAnalysisResult', () {
    const scanlines = [
      ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 10,
        intersectionCount: 2,
        intersections: [
          ScanlineIntersection(
            label: '交点A',
            pixelX: 100,
            pixelY: 200,
            distanceFromStart: 5,
          ),
          ScanlineIntersection(
            label: '交点B',
            pixelX: 300,
            pixelY: 200,
            distanceFromStart: 15,
          ),
        ],
        isValid: true,
      ),
      ScanlineResult(
        name: '竖线1',
        jointSpacing: 0,
        effectiveLength: 0,
        intersectionCount: 0,
        intersections: [],
        isValid: false,
      ),
    ];

    const indicators = ThreeIndicators(
      indicator1: 12.5,
      indicator2: 5,
      indicator3: 2.1,
      totalCracks: 25,
      cracksAbove25cm: 10,
      totalCrackLength: 450,
      imageAreaM2: 0.8,
    );

    test('应该正确创建实例并存储所有字段', () {
      const result = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: indicators,
      );

      expect(result.scanlines, equals(scanlines));
      expect(result.scanlines.length, equals(2));
      expect(result.indicators, equals(indicators));
    });

    test('应该支持空测线列表', () {
      const emptyIndicators = ThreeIndicators(
        indicator1: 0,
        indicator2: 0,
        indicator3: 0,
        totalCracks: 0,
        cracksAbove25cm: 0,
        totalCrackLength: 0,
        imageAreaM2: 1,
      );

      const result = ScanlineAnalysisResult(
        scanlines: [],
        indicators: emptyIndicators,
      );

      expect(result.scanlines, isEmpty);
    });

    test('应该支持 Equatable 值相等比较', () {
      const result1 = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: indicators,
      );
      const result2 = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: indicators,
      );
      const differentIndicators = ThreeIndicators(
        indicator1: 99,
        indicator2: 99,
        indicator3: 99,
        totalCracks: 99,
        cracksAbove25cm: 99,
        totalCrackLength: 9999,
        imageAreaM2: 9,
      );
      const result3 = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: differentIndicators,
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: indicators,
      );

      const newIndicators = ThreeIndicators(
        indicator1: 20,
        indicator2: 10,
        indicator3: 3,
        totalCracks: 40,
        cracksAbove25cm: 20,
        totalCrackLength: 800,
        imageAreaM2: 1.2,
      );

      final updated = original.copyWith(indicators: newIndicators);

      expect(updated.scanlines, equals(scanlines));
      expect(updated.indicators, equals(newIndicators));
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: indicators,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const result = ScanlineAnalysisResult(
        scanlines: scanlines,
        indicators: indicators,
      );

      expect(result.props, equals([scanlines, indicators]));
    });
  });
}
