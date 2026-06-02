import 'dart:io';
import 'dart:math';

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/report_data.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/report_generator_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 随机数据生成器
// ============================================================================

/// 生成随机字符串（用于路径等）
String randomString(Random rng, int minLen, int maxLen) {
  final length = rng.nextInt(maxLen - minLen + 1) + minLen;
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789_/.-';
  return String.fromCharCodes(
    List.generate(length, (_) => chars.codeUnitAt(rng.nextInt(chars.length))),
  );
}

/// 生成随机正 double
double randomPositiveDouble(Random rng, double max) {
  return rng.nextDouble() * max + 0.01;
}

/// 生成随机 ScanlineIntersection
ScanlineIntersection randomIntersection(Random rng, int index) {
  const labels = ['交点A', '交点B', '交点C', '交点D', '交点E', '交点F'];
  return ScanlineIntersection(
    label: index < labels.length ? labels[index] : '交点${index + 1}',
    pixelX: rng.nextInt(2000),
    pixelY: rng.nextInt(2000),
    distanceFromStart: randomPositiveDouble(rng, 500),
  );
}

/// 生成随机 ScanlineResult
ScanlineResult randomScanlineResult(Random rng, String name) {
  final intersectionCount = rng.nextInt(8); // 0-7
  final intersections = List.generate(
    intersectionCount,
    (i) => randomIntersection(rng, i),
  );
  final effectiveLength = intersectionCount > 1
      ? randomPositiveDouble(rng, 500)
      : 0.0;
  final jointSpacing = intersectionCount > 0
      ? effectiveLength / intersectionCount
      : 0.0;

  return ScanlineResult(
    name: name,
    jointSpacing: jointSpacing,
    effectiveLength: effectiveLength,
    intersectionCount: intersectionCount,
    intersections: intersections,
    isValid: intersectionCount > 0,
  );
}

/// 生成随机 CrackInfo
CrackInfo randomCrackInfo(Random rng, int id) {
  final lengthPixels = rng.nextInt(500) + 1;
  final lengthCm = lengthPixels * randomPositiveDouble(rng, 2);
  return CrackInfo(
    id: id,
    lengthCm: lengthCm,
    lengthPixels: lengthPixels,
    x: rng.nextInt(1000),
    y: rng.nextInt(1000),
    w: rng.nextInt(200) + 1,
    h: rng.nextInt(200) + 1,
  );
}

/// 生成随机 ReportData
ReportData randomReportData(Random rng) {
  final scanlineNames = ['横线1', '横线2', '竖线1', '竖线2'];
  final scanlines = scanlineNames
      .map((name) => randomScanlineResult(rng, name))
      .toList();

  final crackCount = rng.nextInt(10); // 0-9
  final cracks = List.generate(crackCount, (i) => randomCrackInfo(rng, i + 1));
  final totalLengthCm = cracks.fold<double>(0, (s, c) => s + c.lengthCm);
  final averageLengthCm = cracks.isEmpty ? 0.0 : totalLengthCm / cracks.length;

  final imageAreaM2 = randomPositiveDouble(rng, 50);

  return ReportData(
    imagePath: '/data/images/${randomString(rng, 3, 15)}.jpg',
    imageWidth: rng.nextInt(3000) + 100,
    imageHeight: rng.nextInt(3000) + 100,
    pixelRatio: randomPositiveDouble(rng, 2),
    rulerLengthCm: randomPositiveDouble(rng, 100),
    scanlineResult: ScanlineAnalysisResult(
      scanlines: scanlines,
      indicators: ThreeIndicators(
        indicator1: randomPositiveDouble(rng, 5),
        indicator2: randomPositiveDouble(rng, 300),
        indicator3: randomPositiveDouble(rng, 5),
        totalCracks: crackCount,
        cracksAbove25cm: rng.nextInt(crackCount + 1),
        totalCrackLength: totalLengthCm,
        imageAreaM2: imageAreaM2,
      ),
    ),
    crackResult: CrackIdentificationResult(
      cracks: cracks,
      totalLengthCm: totalLengthCm,
      averageLengthCm: averageLengthCm,
    ),
    inferenceTimeMs: rng.nextInt(60000) + 100,
    timestamp: DateTime(
      2024 + rng.nextInt(3),
      rng.nextInt(12) + 1,
      rng.nextInt(28) + 1,
      rng.nextInt(24),
      rng.nextInt(60),
      rng.nextInt(60),
    ),
  );
}

void main() {
  late ReportGeneratorService service;

  setUp(() {
    service = ReportGeneratorService();
  });

  // =========================================================================
  // Property 15: 报告内容完整性
  // =========================================================================
  group('ReportGeneratorService - Property 15: 报告内容完整性', () {
    // Feature: jci-calculation, Property 15: 报告内容完整性
    // **Validates: Requirements 11.1-11.9**
    //
    // 对于任意有效的 ReportData，生成的报告文本应包含：图片路径、图片尺寸、
    // 像素比例、三大指标数值、各测线统计数据、裂缝列表中每条裂缝的 ID 和长度、
    // 推理时间。

    test('属性测试: 随机 ReportData 报告内容完整性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final data = randomReportData(random);
        final report = service.generateReport(data);

        // 1. 报告应包含图片路径 (需求 11.2)
        expect(
          report.contains(data.imagePath),
          isTrue,
          reason: '迭代 $i: 报告应包含图片路径 "${data.imagePath}"',
        );

        // 2. 报告应包含图片尺寸 (需求 11.2)
        expect(
          report.contains('${data.imageWidth} x ${data.imageHeight} 像素'),
          isTrue,
          reason:
              '迭代 $i: 报告应包含图片尺寸 '
              '"${data.imageWidth} x ${data.imageHeight} 像素"',
        );

        // 3. 报告应包含像素比例 (需求 11.2)
        final pixelRatioStr = data.pixelRatio.toStringAsFixed(4);
        expect(
          report.contains(pixelRatioStr),
          isTrue,
          reason: '迭代 $i: 报告应包含像素比例 "$pixelRatioStr"',
        );

        // 4. 报告应包含三大指标数值 (需求 11.3)
        final ind = data.scanlineResult.indicators;
        expect(
          report.contains(ind.indicator1.toStringAsFixed(4)),
          isTrue,
          reason: '迭代 $i: 报告应包含指标1值',
        );
        expect(
          report.contains(ind.indicator2.toStringAsFixed(2)),
          isTrue,
          reason: '迭代 $i: 报告应包含指标2值',
        );
        expect(
          report.contains(ind.indicator3.toStringAsFixed(4)),
          isTrue,
          reason: '迭代 $i: 报告应包含指标3值',
        );

        // 5. 报告应包含各测线统计数据 (需求 11.4)
        for (final scanline in data.scanlineResult.scanlines) {
          expect(
            report.contains(scanline.name),
            isTrue,
            reason: '迭代 $i: 报告应包含测线名称 "${scanline.name}"',
          );
        }

        // 6. 报告应包含裂缝列表中每条裂缝的 ID 和长度 (需求 11.6)
        for (final crack in data.crackResult.cracks) {
          expect(
            report.contains(crack.id.toString()),
            isTrue,
            reason: '迭代 $i: 报告应包含裂缝 ID ${crack.id}',
          );
          expect(
            report.contains(crack.lengthCm.toStringAsFixed(2)),
            isTrue,
            reason:
                '迭代 $i: 报告应包含裂缝长度 '
                '${crack.lengthCm.toStringAsFixed(2)}',
          );
        }

        // 7. 报告应包含推理时间 (需求 11.7)
        final inferenceSeconds = data.inferenceTimeMs / 1000;
        expect(
          report.contains(inferenceSeconds.toStringAsFixed(2)),
          isTrue,
          reason:
              '迭代 $i: 报告应包含推理时间 '
              '"${inferenceSeconds.toStringAsFixed(2)}s"',
        );
      }
    });
  });

  // =========================================================================
  // Property 16: 报告保存往返一致性
  // =========================================================================
  group('ReportGeneratorService - Property 16: 报告保存往返一致性', () {
    // Feature: jci-calculation, Property 16: 报告保存往返一致性
    // **Validates: Requirements 11.1-11.9**
    //
    // 对于任意有效的报告文本内容，保存为 .txt 文件后再读取，
    // 应得到与原内容完全相同的文本。

    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('report_pbt_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('属性测试: 随机报告文本保存往返一致性 (100 次迭代)', () async {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        // 生成随机 ReportData 并生成报告文本
        final data = randomReportData(random);
        final reportContent = service.generateReport(data);

        // 保存报告到文件
        final fileName = 'pbt_report_$i.txt';
        final filePath = await service.saveReport(
          content: reportContent,
          outputDir: tempDir.path,
          fileName: fileName,
        );

        // 读取保存的文件
        final savedContent = File(filePath).readAsStringSync();

        // 验证往返一致性：读取的内容应与原内容完全相同
        expect(
          savedContent,
          equals(reportContent),
          reason:
              '迭代 $i: 保存后读取的报告内容应与原内容完全相同。'
              '\n原内容长度: ${reportContent.length}'
              '\n读取内容长度: ${savedContent.length}',
        );
      }
    });
  });
}
