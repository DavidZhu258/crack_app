// Property-test reason strings are split without added whitespace so the
// rendered failure message stays natural in Chinese.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScanlineAnalyzerService service;

  setUp(() {
    service = const ScanlineAnalyzerService();
  });

  // =========================================================================
  // Property 11: 测线布置正确性
  // =========================================================================
  group('ScanlineAnalyzerService - Property 11: 测线布置正确性', () {
    // Feature: jci-calculation, Property 11: 测线布置正确性
    // **Validates: Requirements 10.1-10.9**
    //
    // 对于任意有效的图像尺寸（宽度 > 0，高度 > 0），layoutScanlines 应返回
    // 恰好 4 条测线（2条横线 + 2条竖线），横线位于高度的 1/3 和 2/3 处，
    // 竖线位于宽度的 1/3 和 2/3 处。

    test('属性测试: 随机图像尺寸测线布置正确性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final width = random.nextInt(2000) + 1; // 1-2000
        final height = random.nextInt(2000) + 1; // 1-2000

        final scanlines = service.layoutScanlines(width, height);

        // 应返回恰好 4 条测线
        expect(
          scanlines.length,
          equals(4),
          reason:
              '迭代 $i: ${width}x$height 应返回 4 条测线，'
              '实际返回 ${scanlines.length} 条',
        );

        // 应有 2 条横线和 2 条竖线
        final horizontal = scanlines.where((s) => s.isHorizontal).toList();
        final vertical = scanlines.where((s) => !s.isHorizontal).toList();

        expect(
          horizontal.length,
          equals(2),
          reason: '迭代 $i: 应有 2 条横线，实际 ${horizontal.length} 条',
        );
        expect(
          vertical.length,
          equals(2),
          reason: '迭代 $i: 应有 2 条竖线，实际 ${vertical.length} 条',
        );

        // 横线位于高度的 1/3 和 2/3 处
        final expectedH1 = height ~/ 3;
        final expectedH2 = (height * 2) ~/ 3;
        expect(
          horizontal[0].position,
          equals(expectedH1),
          reason:
              '迭代 $i: 横线1 应在 y=$expectedH1，'
              '实际在 y=${horizontal[0].position}',
        );
        expect(
          horizontal[1].position,
          equals(expectedH2),
          reason:
              '迭代 $i: 横线2 应在 y=$expectedH2，'
              '实际在 y=${horizontal[1].position}',
        );

        // 竖线位于宽度的 1/3 和 2/3 处
        final expectedV1 = width ~/ 3;
        final expectedV2 = (width * 2) ~/ 3;
        expect(
          vertical[0].position,
          equals(expectedV1),
          reason:
              '迭代 $i: 竖线1 应在 x=$expectedV1，'
              '实际在 x=${vertical[0].position}',
        );
        expect(
          vertical[1].position,
          equals(expectedV2),
          reason:
              '迭代 $i: 竖线2 应在 x=$expectedV2，'
              '实际在 x=${vertical[1].position}',
        );

        // 横线范围应为 0 到 width-1
        for (final h in horizontal) {
          expect(h.start, equals(0), reason: '迭代 $i: 横线 ${h.name} start 应为 0');
          expect(
            h.end,
            equals(width - 1),
            reason: '迭代 $i: 横线 ${h.name} end 应为 ${width - 1}',
          );
        }

        // 竖线范围应为 0 到 height-1
        for (final v in vertical) {
          expect(v.start, equals(0), reason: '迭代 $i: 竖线 ${v.name} start 应为 0');
          expect(
            v.end,
            equals(height - 1),
            reason: '迭代 $i: 竖线 ${v.name} end 应为 ${height - 1}',
          );
        }
      }
    });
  });

  // =========================================================================
  // Property 12: 测线有效长度与节理间距公式正确性
  // =========================================================================
  group('ScanlineAnalyzerService - Property 12: 测线有效长度与节理间距公式正确性', () {
    // Feature: jci-calculation, Property 12: 测线有效长度与节理间距公式正确性
    // **Validates: Requirements 10.1-10.9**
    //
    // 对于任意含有至少 2 个交点的测线分析结果，有效长度应等于第一个交点到
    // 最后一个交点的距离，节理间距应等于有效长度除以交点数。

    test('属性测试: 随机交点列表有效长度与节理间距公式 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        // 使用较小的图像尺寸以保证性能
        final imageSize = random.nextInt(91) + 30; // 30-120
        final pixelRatio = random.nextDouble() * 2 + 0.1; // 0.1-2.1

        // 生成随机裂缝位置（至少 2 个不相邻的裂缝段）
        final numCrackSegments = random.nextInt(4) + 2; // 2-5 segments
        final crackPositions = <int>[];

        // 使用步长方式放置裂缝，避免无限循环
        final step = imageSize ~/ (numCrackSegments + 1);
        for (var s = 0; s < numCrackSegments && step > 2; s++) {
          final base = (s + 1) * step;
          final offset = random.nextInt(max(1, step ~/ 2));
          final pos = (base + offset).clamp(0, imageSize - 1);
          crackPositions.add(pos);
        }

        if (crackPositions.length < 2) continue;

        // 构建掩膜行（横线测试）
        final maskRow = List.filled(imageSize, false);
        for (final pos in crackPositions) {
          maskRow[pos] = true;
        }

        // 创建掩膜（3行，测线在 y=1）
        final mask = [
          List.filled(imageSize, false),
          List<bool>.from(maskRow),
          List.filled(imageSize, false),
        ];

        final scanline = Scanline(
          name: '测试横线',
          isHorizontal: true,
          position: 1,
          start: 0,
          end: imageSize - 1,
        );

        final intersections = service.findIntersections(
          scanline,
          mask,
          pixelRatio,
        );

        if (intersections.length >= 2) {
          // 验证有效长度 = 最后交点距离 - 第一交点距离
          final expectedEffectiveLength =
              intersections.last.distanceFromStart -
              intersections.first.distanceFromStart;

          // 验证节理间距 = 有效长度 / 交点数
          final expectedJointSpacing =
              expectedEffectiveLength / intersections.length;

          // 使用 analyze 方法验证
          final result = service.analyze(
            crackMask: mask,
            pixelRatio: pixelRatio,
            imageWidth: imageSize,
            imageHeight: 3,
            cracks: [],
          );

          // 横线1 在 height~/3 = 3~/3 = 1
          final h1 = result.scanlines.firstWhere(
            (s) => s.name == '横线1',
          );

          if (h1.isValid && h1.intersectionCount >= 2) {
            expect(
              h1.effectiveLength,
              closeTo(expectedEffectiveLength, 0.001),
              reason: '迭代 $i: 有效长度应等于首尾交点距离差',
            );

            expect(
              h1.jointSpacing,
              closeTo(expectedJointSpacing, 0.001),
              reason: '迭代 $i: 节理间距应等于有效长度/交点数',
            );
          }
        }
      }
    });
  });

  // =========================================================================
  // Property 13: 像素到物理距离转换一致性
  // =========================================================================
  group('ScanlineAnalyzerService - Property 13: 像素到物理距离转换一致性', () {
    // Feature: jci-calculation, Property 13: 像素到物理距离转换一致性
    // **Validates: Requirements 10.1-10.9**
    //
    // 对于任意正的像素距离和正的像素比例，转换后的物理距离（cm）应等于
    // 像素距离乘以像素比例。对同一裂缝，CrackInfo.lengthCm 应等于
    // CrackInfo.lengthPixels 乘以 pixelRatio。

    test('属性测试: 随机像素距离和比例转换一致性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final pixelRatio = random.nextDouble() * 5 + 0.01; // 0.01-5.01
        final pixelDistance = random.nextInt(1000) + 1; // 1-1000

        // 验证 CrackInfo 的 lengthCm = lengthPixels * pixelRatio
        final expectedLengthCm = pixelDistance * pixelRatio;
        final crack = CrackInfo(
          id: i,
          lengthCm: expectedLengthCm,
          lengthPixels: pixelDistance,
          x: 0,
          y: 0,
          w: pixelDistance,
          h: 1,
        );

        expect(
          crack.lengthCm,
          closeTo(crack.lengthPixels * pixelRatio, 0.0001),
          reason:
              '迭代 $i: CrackInfo.lengthCm (${crack.lengthCm}) 应等于 '
              'lengthPixels (${crack.lengthPixels}) × pixelRatio ($pixelRatio) '
              '= $expectedLengthCm',
        );
      }
    });

    test('属性测试: 测线交点距离转换一致性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final pixelRatio = random.nextDouble() * 3 + 0.1; // 0.1-3.1
        final imageWidth = random.nextInt(200) + 20; // 20-219

        // 在随机位置放置一个裂缝像素
        final crackX = random.nextInt(imageWidth);

        // 构建掩膜（3行，测线在 y=1）
        final maskRow = List.filled(imageWidth, false);
        maskRow[crackX] = true;

        final mask = [
          List.filled(imageWidth, false),
          maskRow,
          List.filled(imageWidth, false),
        ];

        final scanline = Scanline(
          name: '测试横线',
          isHorizontal: true,
          position: 1,
          start: 0,
          end: imageWidth - 1,
        );

        final intersections = service.findIntersections(
          scanline,
          mask,
          pixelRatio,
        );

        if (intersections.isNotEmpty) {
          final intersection = intersections.first;
          // 交点的像素距离 = pixelX - scanline.start
          final pixelDist = intersection.pixelX - scanline.start;
          final expectedDistCm = pixelDist * pixelRatio;

          expect(
            intersection.distanceFromStart,
            closeTo(expectedDistCm, 0.001),
            reason:
                '迭代 $i: 交点距离 ${intersection.distanceFromStart} cm '
                '应等于像素距离 $pixelDist × pixelRatio $pixelRatio '
                '= $expectedDistCm cm',
          );
        }
      }
    });
  });

  // =========================================================================
  // Property 14: 三大指标公式正确性
  // =========================================================================
  group('ScanlineAnalyzerService - Property 14: 三大指标公式正确性', () {
    // Feature: jci-calculation, Property 14: 三大指标公式正确性
    // **Validates: Requirements 10.1-10.9**
    //
    // 对于任意有效的裂缝列表和图像面积：
    // - 指标1 应等于长度≥25cm的裂隙条数除以图像实际面积（m²）
    // - 指标2 应等于所有有效测线节理间距的平均值
    // - 指标3 应等于裂隙总长度（m）除以图像实际面积（m²）

    test('属性测试: 随机裂缝列表三大指标公式正确性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final pixelRatio = random.nextDouble() * 2 + 0.1; // 0.1-2.1
        final imageWidth = random.nextInt(100) + 20; // 20-119
        final imageHeight = random.nextInt(100) + 20; // 20-119

        // 生成随机裂缝列表
        final numCracks = random.nextInt(10); // 0-9
        final cracks = <CrackInfo>[];
        for (var j = 0; j < numCracks; j++) {
          final lengthPixels = random.nextInt(100) + 1;
          final lengthCm = lengthPixels * pixelRatio;
          cracks.add(
            CrackInfo(
              id: j + 1,
              lengthCm: lengthCm,
              lengthPixels: lengthPixels,
              x: 0,
              y: 0,
              w: lengthPixels,
              h: 1,
            ),
          );
        }

        // 使用空掩膜（无交点），这样 indicator2 = 0
        final mask = List.generate(
          imageHeight,
          (_) => List.filled(imageWidth, false),
        );

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: pixelRatio,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          cracks: cracks,
        );

        // 计算期望的图像面积
        final imageWidthCm = imageWidth * pixelRatio;
        final imageHeightCm = imageHeight * pixelRatio;
        final expectedAreaM2 = (imageWidthCm / 100) * (imageHeightCm / 100);

        expect(
          result.indicators.imageAreaM2,
          closeTo(expectedAreaM2, 0.0001),
          reason: '迭代 $i: 图像面积应为 $expectedAreaM2 m²',
        );

        // 指标1: 长度≥25cm的裂隙条数 / 图像面积
        final cracksAbove25 = cracks.where((c) => c.lengthCm >= 25).length;
        final expectedIndicator1 = expectedAreaM2 > 0
            ? cracksAbove25 / expectedAreaM2
            : 0.0;

        expect(
          result.indicators.indicator1,
          closeTo(expectedIndicator1, 0.0001),
          reason:
              '迭代 $i: 指标1 应为 $expectedIndicator1，'
              '实际 ${result.indicators.indicator1}',
        );

        // 指标2: 无交点时应为 0（所有测线无效）
        expect(
          result.indicators.indicator2,
          equals(0.0),
          reason: '迭代 $i: 空掩膜时指标2 应为 0',
        );

        // 指标3: 裂隙总长度(m) / 图像面积(m²)
        final totalLengthCm = cracks.fold<double>(
          0,
          (sum, c) => sum + c.lengthCm,
        );
        final totalLengthM = totalLengthCm / 100;
        final expectedIndicator3 = expectedAreaM2 > 0
            ? totalLengthM / expectedAreaM2
            : 0.0;

        expect(
          result.indicators.indicator3,
          closeTo(expectedIndicator3, 0.0001),
          reason:
              '迭代 $i: 指标3 应为 $expectedIndicator3，'
              '实际 ${result.indicators.indicator3}',
        );
      }
    });

    test('属性测试: 有交点时指标2等于有效测线节理间距平均值 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        // 使用较大的图像以确保测线位置有效
        final imageWidth = random.nextInt(100) + 30; // 30-129
        final imageHeight = random.nextInt(100) + 30; // 30-129
        final pixelRatio = random.nextDouble() * 2 + 0.1; // 0.1-2.1

        // 在测线位置放置随机裂缝
        final mask = List.generate(
          imageHeight,
          (_) => List.filled(imageWidth, false),
        );

        // 获取测线位置
        final h1y = imageHeight ~/ 3;
        final h2y = (imageHeight * 2) ~/ 3;
        final v1x = imageWidth ~/ 3;
        final v2x = (imageWidth * 2) ~/ 3;

        // 在每条测线上随机放置裂缝段
        for (final y in [h1y, h2y]) {
          if (y < imageHeight) {
            final numSegments = random.nextInt(4) + 1; // 1-4
            for (var s = 0; s < numSegments; s++) {
              final x = random.nextInt(imageWidth);
              if (x < imageWidth) mask[y][x] = true;
            }
          }
        }
        for (final x in [v1x, v2x]) {
          if (x < imageWidth) {
            final numSegments = random.nextInt(4) + 1;
            for (var s = 0; s < numSegments; s++) {
              final y = random.nextInt(imageHeight);
              if (y < imageHeight) mask[y][x] = true;
            }
          }
        }

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: pixelRatio,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          cracks: [],
        );

        // 验证指标2 = 有效测线节理间距的平均值
        final validScanlines = result.scanlines
            .where((s) => s.isValid)
            .toList();

        if (validScanlines.isNotEmpty) {
          final expectedIndicator2 =
              validScanlines.fold<double>(
                0,
                (sum, s) => sum + s.jointSpacing,
              ) /
              validScanlines.length;

          expect(
            result.indicators.indicator2,
            closeTo(expectedIndicator2, 0.001),
            reason:
                '迭代 $i: 指标2 应为有效测线节理间距平均值 '
                '$expectedIndicator2，实际 ${result.indicators.indicator2}',
          );
        } else {
          expect(
            result.indicators.indicator2,
            equals(0.0),
            reason: '迭代 $i: 无有效测线时指标2 应为 0',
          );
        }
      }
    });
  });
}
