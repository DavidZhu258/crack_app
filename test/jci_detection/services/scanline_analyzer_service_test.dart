import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScanlineAnalyzerService service;

  setUp(() {
    service = const ScanlineAnalyzerService();
  });

  /// 辅助方法：从字符串模式创建掩膜
  /// '#' 表示裂缝像素，'.' 表示非裂缝像素
  List<List<bool>> maskFromPattern(List<String> pattern) {
    return pattern
        .map((row) => row.split('').map((c) => c == '#').toList())
        .toList();
  }

  group('ScanlineAnalyzerService', () {
    group('layoutScanlines', () {
      test('应返回恰好 4 条测线', () {
        final scanlines = service.layoutScanlines(300, 300);
        expect(scanlines.length, equals(4));
      });

      test('应包含 2 条横线和 2 条竖线', () {
        final scanlines = service.layoutScanlines(300, 300);
        final horizontal = scanlines.where((s) => s.isHorizontal).toList();
        final vertical = scanlines.where((s) => !s.isHorizontal).toList();

        expect(horizontal.length, equals(2));
        expect(vertical.length, equals(2));
      });

      test('横线应位于高度的 1/3 和 2/3 处', () {
        final scanlines = service.layoutScanlines(300, 300);
        final horizontal = scanlines.where((s) => s.isHorizontal).toList();

        expect(horizontal[0].position, equals(100)); // 300 ~/ 3 = 100
        expect(horizontal[1].position, equals(200)); // (300 * 2) ~/ 3 = 200
      });

      test('竖线应位于宽度的 1/3 和 2/3 处', () {
        final scanlines = service.layoutScanlines(300, 300);
        final vertical = scanlines.where((s) => !s.isHorizontal).toList();

        expect(vertical[0].position, equals(100)); // 300 ~/ 3 = 100
        expect(vertical[1].position, equals(200)); // (300 * 2) ~/ 3 = 200
      });

      test('横线应从 0 到 width-1', () {
        final scanlines = service.layoutScanlines(300, 300);
        final horizontal = scanlines.where((s) => s.isHorizontal).toList();

        for (final line in horizontal) {
          expect(line.start, equals(0));
          expect(line.end, equals(299));
        }
      });

      test('竖线应从 0 到 height-1', () {
        final scanlines = service.layoutScanlines(300, 300);
        final vertical = scanlines.where((s) => !s.isHorizontal).toList();

        for (final line in vertical) {
          expect(line.start, equals(0));
          expect(line.end, equals(299));
        }
      });

      test('非整除尺寸应使用整数除法', () {
        final scanlines = service.layoutScanlines(100, 100);
        final horizontal = scanlines.where((s) => s.isHorizontal).toList();
        final vertical = scanlines.where((s) => !s.isHorizontal).toList();

        expect(horizontal[0].position, equals(33)); // 100 ~/ 3 = 33
        expect(horizontal[1].position, equals(66)); // (100 * 2) ~/ 3 = 66
        expect(vertical[0].position, equals(33));
        expect(vertical[1].position, equals(66));
      });

      test('测线名称应正确', () {
        final scanlines = service.layoutScanlines(300, 300);

        expect(scanlines[0].name, equals('横线1'));
        expect(scanlines[1].name, equals('横线2'));
        expect(scanlines[2].name, equals('竖线1'));
        expect(scanlines[3].name, equals('竖线2'));
      });
    });

    group('findIntersections', () {
      test('全黑掩膜应返回空交点列表', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections, isEmpty);
      });

      test('横线穿过单个裂缝段应返回 1 个交点', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '...###...',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections.length, equals(1));
        // 裂缝段从 x=3 到 x=5，中点为 (3+5)~/2 = 4
        expect(intersections[0].pixelX, equals(4));
        expect(intersections[0].pixelY, equals(3));
      });

      test('横线穿过两个裂缝段应返回 2 个交点', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.##..##..',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections.length, equals(2));
      });

      test('竖线穿过裂缝段应返回正确交点', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '...#.....',
          '...#.....',
          '...#.....',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const scanline = Scanline(
          name: '竖线1',
          isHorizontal: false,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections.length, equals(1));
        // 裂缝段从 y=2 到 y=4，中点为 (2+4)~/2 = 3
        expect(intersections[0].pixelX, equals(3));
        expect(intersections[0].pixelY, equals(3));
      });

      test('像素比例应正确应用于距离计算', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '....#....',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const pixelRatio = 0.5;
        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(
          scanline,
          mask,
          pixelRatio,
        );
        expect(intersections.length, equals(1));
        // 单像素裂缝在 x=4，中点为 4
        // 距离起点 = 4 像素 * 0.5 cm/像素 = 2.0 cm
        expect(intersections[0].distanceFromStart, closeTo(2.0, 0.001));
      });

      test('测线末端在裂缝中应正确处理', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.......##',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections.length, equals(1));
      });

      test('交点标签应按顺序命名', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.#..#..#.',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 3,
          start: 0,
          end: 8,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections.length, equals(3));
        expect(intersections[0].label, equals('交点A'));
        expect(intersections[1].label, equals('交点B'));
        expect(intersections[2].label, equals('交点C'));
      });

      test('测线位置超出掩膜范围应返回空列表', () {
        final mask = maskFromPattern([
          '###',
          '###',
          '###',
        ]);

        const scanline = Scanline(
          name: '横线1',
          isHorizontal: true,
          position: 10, // 超出范围
          start: 0,
          end: 2,
        );

        final intersections = service.findIntersections(scanline, mask, 1);
        expect(intersections, isEmpty);
      });
    });

    group('analyze', () {
      test('空掩膜应返回三大指标均为 0', () {
        final result = service.analyze(
          crackMask: [],
          pixelRatio: 1,
          imageWidth: 100,
          imageHeight: 100,
          cracks: [],
        );

        expect(result.indicators.indicator1, equals(0));
        expect(result.indicators.indicator2, equals(0));
        expect(result.indicators.indicator3, equals(0));
      });

      test('全黑掩膜应返回所有测线无效', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        for (final scanline in result.scanlines) {
          expect(scanline.isValid, isFalse);
          expect(scanline.intersectionCount, equals(0));
        }
      });

      test('应返回恰好 4 条测线结果', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        expect(result.scanlines.length, equals(4));
      });

      test('有交点的测线应标记为有效', () {
        // 9x9 掩膜，横线1在 y=3，竖线1在 x=3
        // 在 (3,3) 放置裂缝，横线1和竖线1都应有交点
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '...#.....',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        // 横线1 在 y = 9~/3 = 3，应与 (3,3) 处的裂缝相交
        final h1 = result.scanlines.firstWhere((s) => s.name == '横线1');
        expect(h1.isValid, isTrue);
        expect(h1.intersectionCount, equals(1));

        // 竖线1 在 x = 9~/3 = 3，应与 (3,3) 处的裂缝相交
        final v1 = result.scanlines.firstWhere((s) => s.name == '竖线1');
        expect(v1.isValid, isTrue);
        expect(v1.intersectionCount, equals(1));
      });

      test('无交点的测线应排除出平均值计算', () {
        // 只在横线1的路径上放置裂缝
        // 9x9 掩膜，横线1在 y=3
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.#...#...',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        // 横线1 应有效（有交点）
        final h1 = result.scanlines.firstWhere((s) => s.name == '横线1');
        expect(h1.isValid, isTrue);

        // 指标2 应只基于有效测线计算
        final validScanlines = result.scanlines
            .where((s) => s.isValid)
            .toList();
        if (validScanlines.isNotEmpty) {
          final expectedAvg =
              validScanlines.fold<double>(
                0,
                (sum, s) => sum + s.jointSpacing,
              ) /
              validScanlines.length;
          expect(
            result.indicators.indicator2,
            closeTo(expectedAvg, 0.001),
          );
        }
      });

      test('有效长度应等于第一个交点到最后一个交点的距离', () {
        // 在横线1路径上放置两个裂缝段
        // 9x9 掩膜，横线1在 y=3
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.#.....#.',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        final h1 = result.scanlines.firstWhere((s) => s.name == '横线1');
        expect(h1.isValid, isTrue);
        expect(h1.intersectionCount, equals(2));

        // 有效长度 = 最后交点距离 - 第一交点距离
        final expectedLength =
            h1.intersections.last.distanceFromStart -
            h1.intersections.first.distanceFromStart;
        expect(h1.effectiveLength, closeTo(expectedLength, 0.001));
      });

      test('节理间距应等于有效长度除以交点数', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.#...#...',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        final h1 = result.scanlines.firstWhere((s) => s.name == '横线1');
        if (h1.isValid && h1.intersectionCount > 0) {
          final expectedSpacing = h1.effectiveLength / h1.intersectionCount;
          expect(h1.jointSpacing, closeTo(expectedSpacing, 0.001));
        }
      });

      test('像素比例为 0 时应使用默认值 1.0', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '...#.....',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 0,
          imageWidth: 9,
          imageHeight: 9,
          cracks: [],
        );

        // 应正常返回结果（不会除以零）
        expect(result.scanlines.length, equals(4));
        expect(result.indicators.imageAreaM2, greaterThan(0));
      });

      test('指标1 应正确计算长度≥25cm的裂隙条数/面积', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final cracks = [
          const CrackInfo(
            id: 1,
            lengthCm: 30,
            lengthPixels: 30,
            x: 0,
            y: 0,
            w: 30,
            h: 1,
          ),
          const CrackInfo(
            id: 2,
            lengthCm: 20,
            lengthPixels: 20,
            x: 0,
            y: 2,
            w: 20,
            h: 1,
          ),
          const CrackInfo(
            id: 3,
            lengthCm: 25,
            lengthPixels: 25,
            x: 0,
            y: 4,
            w: 25,
            h: 1,
          ),
        ];

        // pixelRatio=1, imageWidth=9, imageHeight=9
        // imageArea = (9*1/100) * (9*1/100) = 0.09 * 0.09 = 0.0081 m²
        // cracksAbove25cm = 2 (30cm and 25cm)
        // indicator1 = 2 / 0.0081
        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: cracks,
        );

        expect(result.indicators.cracksAbove25cm, equals(2));
        expect(result.indicators.totalCracks, equals(3));

        const expectedArea = (9.0 / 100) * (9.0 / 100);
        expect(
          result.indicators.indicator1,
          closeTo(2 / expectedArea, 0.001),
        );
      });

      test('指标3 应正确计算裂隙总长度/面积', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        final cracks = [
          const CrackInfo(
            id: 1,
            lengthCm: 50,
            lengthPixels: 50,
            x: 0,
            y: 0,
            w: 50,
            h: 1,
          ),
          const CrackInfo(
            id: 2,
            lengthCm: 30,
            lengthPixels: 30,
            x: 0,
            y: 2,
            w: 30,
            h: 1,
          ),
        ];

        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 1,
          imageWidth: 9,
          imageHeight: 9,
          cracks: cracks,
        );

        // totalCrackLength = 50 + 30 = 80 cm = 0.8 m
        // imageArea = 0.0081 m²
        // indicator3 = 0.8 / 0.0081
        const expectedArea = (9.0 / 100) * (9.0 / 100);
        const expectedIndicator3 = (80.0 / 100) / expectedArea;
        expect(
          result.indicators.indicator3,
          closeTo(expectedIndicator3, 0.001),
        );
        expect(result.indicators.totalCrackLength, closeTo(80, 0.001));
      });

      test('图像面积应正确计算', () {
        final mask = maskFromPattern([
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
          '.........',
        ]);

        // pixelRatio=0.5, width=200, height=100
        // widthCm = 200 * 0.5 = 100 cm = 1 m
        // heightCm = 100 * 0.5 = 50 cm = 0.5 m
        // area = 1 * 0.5 = 0.5 m²
        final result = service.analyze(
          crackMask: mask,
          pixelRatio: 0.5,
          imageWidth: 200,
          imageHeight: 100,
          cracks: [],
        );

        expect(result.indicators.imageAreaM2, closeTo(0.5, 0.001));
      });
    });
  });
}
