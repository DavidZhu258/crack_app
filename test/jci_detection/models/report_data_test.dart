import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/report_data.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Shared test data
  const testScanlineResult = ScanlineAnalysisResult(
    scanlines: [
      ScanlineResult(
        name: '横线1',
        jointSpacing: 5,
        effectiveLength: 20,
        intersectionCount: 4,
        intersections: [
          ScanlineIntersection(
            label: '交点A',
            pixelX: 100,
            pixelY: 200,
            distanceFromStart: 5,
          ),
        ],
        isValid: true,
      ),
    ],
    indicators: ThreeIndicators(
      indicator1: 2.5,
      indicator2: 5,
      indicator3: 1.2,
      totalCracks: 10,
      cracksAbove25cm: 5,
      totalCrackLength: 150,
      imageAreaM2: 2,
    ),
  );

  const testCrackResult = CrackIdentificationResult(
    cracks: [
      CrackInfo(
        id: 1,
        lengthCm: 30,
        lengthPixels: 600,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      ),
      CrackInfo(
        id: 2,
        lengthCm: 15,
        lengthPixels: 300,
        x: 50,
        y: 60,
        w: 80,
        h: 40,
      ),
    ],
    totalLengthCm: 45,
    averageLengthCm: 22.5,
  );

  final testTimestamp = DateTime(2024, 1, 15, 10, 30);

  group('ReportData', () {
    test('应该正确创建实例并存储所有字段', () {
      final reportData = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      expect(reportData.imagePath, equals('/path/to/image.jpg'));
      expect(reportData.imageWidth, equals(1920));
      expect(reportData.imageHeight, equals(1080));
      expect(reportData.pixelRatio, equals(0.05));
      expect(reportData.rulerLengthCm, equals(30.0));
      expect(reportData.scanlineResult, equals(testScanlineResult));
      expect(reportData.crackResult, equals(testCrackResult));
      expect(reportData.inferenceTimeMs, equals(1500));
      expect(reportData.timestamp, equals(testTimestamp));
    });

    test('应该支持 Equatable 值相等比较', () {
      final reportData1 = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );
      final reportData2 = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );
      final reportData3 = ReportData(
        imagePath: '/path/to/other.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      expect(reportData1, equals(reportData2));
      expect(reportData1, isNot(equals(reportData3)));
    });

    test('不同字段值应导致不相等', () {
      final base = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      // 不同的 imageWidth
      final differentWidth = base.copyWith(imageWidth: 1280);
      expect(base, isNot(equals(differentWidth)));

      // 不同的 pixelRatio
      final differentRatio = base.copyWith(pixelRatio: 0.1);
      expect(base, isNot(equals(differentRatio)));

      // 不同的 inferenceTimeMs
      final differentTime = base.copyWith(inferenceTimeMs: 2000);
      expect(base, isNot(equals(differentTime)));

      // 不同的 timestamp
      final differentTimestamp = base.copyWith(
        timestamp: DateTime(2024, 2),
      );
      expect(base, isNot(equals(differentTimestamp)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      final original = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      final updated = original.copyWith(
        imagePath: '/new/path.jpg',
        imageWidth: 1280,
        inferenceTimeMs: 2000,
      );

      expect(updated.imagePath, equals('/new/path.jpg'));
      expect(updated.imageWidth, equals(1280));
      expect(updated.imageHeight, equals(1080));
      expect(updated.pixelRatio, equals(0.05));
      expect(updated.rulerLengthCm, equals(30.0));
      expect(updated.scanlineResult, equals(testScanlineResult));
      expect(updated.crackResult, equals(testCrackResult));
      expect(updated.inferenceTimeMs, equals(2000));
      expect(updated.timestamp, equals(testTimestamp));
    });

    test('copyWith 不传参数应返回等价实例', () {
      final original = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('copyWith 应该能更新所有字段', () {
      final original = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      const newScanlineResult = ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 0,
          indicator2: 0,
          indicator3: 0,
          totalCracks: 0,
          cracksAbove25cm: 0,
          totalCrackLength: 0,
          imageAreaM2: 1,
        ),
      );

      const newCrackResult = CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 0,
        averageLengthCm: 0,
      );

      final newTimestamp = DateTime(2025, 6);

      final updated = original.copyWith(
        imagePath: '/new/path.jpg',
        imageWidth: 640,
        imageHeight: 480,
        pixelRatio: 0.1,
        rulerLengthCm: 15,
        scanlineResult: newScanlineResult,
        crackResult: newCrackResult,
        inferenceTimeMs: 500,
        timestamp: newTimestamp,
      );

      expect(updated.imagePath, equals('/new/path.jpg'));
      expect(updated.imageWidth, equals(640));
      expect(updated.imageHeight, equals(480));
      expect(updated.pixelRatio, equals(0.1));
      expect(updated.rulerLengthCm, equals(15.0));
      expect(updated.scanlineResult, equals(newScanlineResult));
      expect(updated.crackResult, equals(newCrackResult));
      expect(updated.inferenceTimeMs, equals(500));
      expect(updated.timestamp, equals(newTimestamp));
    });

    test('props 应包含所有字段', () {
      final reportData = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 1920,
        imageHeight: 1080,
        pixelRatio: 0.05,
        rulerLengthCm: 30,
        scanlineResult: testScanlineResult,
        crackResult: testCrackResult,
        inferenceTimeMs: 1500,
        timestamp: testTimestamp,
      );

      expect(
        reportData.props,
        equals([
          '/path/to/image.jpg',
          1920,
          1080,
          0.05,
          30.0,
          testScanlineResult,
          testCrackResult,
          1500,
          testTimestamp,
          null,
          null,
          null,
          null,
          null,
          null,
        ]),
      );
    });

    test('应该支持空裂缝列表和空测线列表', () {
      const emptyScanlineResult = ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 0,
          indicator2: 0,
          indicator3: 0,
          totalCracks: 0,
          cracksAbove25cm: 0,
          totalCrackLength: 0,
          imageAreaM2: 1,
        ),
      );

      const emptyCrackResult = CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 0,
        averageLengthCm: 0,
      );

      final reportData = ReportData(
        imagePath: '/path/to/image.jpg',
        imageWidth: 100,
        imageHeight: 100,
        pixelRatio: 1,
        rulerLengthCm: 10,
        scanlineResult: emptyScanlineResult,
        crackResult: emptyCrackResult,
        inferenceTimeMs: 0,
        timestamp: testTimestamp,
      );

      expect(reportData.scanlineResult.scanlines, isEmpty);
      expect(reportData.crackResult.cracks, isEmpty);
      expect(reportData.inferenceTimeMs, equals(0));
    });
  });
}
