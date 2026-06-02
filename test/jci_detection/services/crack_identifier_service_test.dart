// Property-test reason strings are split without added whitespace so the
// rendered failure message stays natural in Chinese.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:crack_app/jci_detection/services/crack_identifier_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CrackIdentifierService service;

  setUp(() {
    service = const CrackIdentifierService();
  });

  /// 辅助方法：从字符串模式创建掩膜
  /// '#' 表示裂缝像素，'.' 表示非裂缝像素
  List<List<bool>> maskFromPattern(List<String> pattern) {
    return pattern
        .map((row) => row.split('').map((c) => c == '#').toList())
        .toList();
  }

  /// 辅助方法：生成随机二值掩膜
  /// [width] 和 [height] 为掩膜尺寸
  /// [density] 为裂缝像素密度 (0.0-1.0)
  List<List<bool>> generateRandomMask(
    Random random,
    int width,
    int height,
    double density,
  ) {
    return List.generate(
      height,
      (_) => List.generate(width, (_) => random.nextDouble() < density),
    );
  }

  /// 辅助方法：独立计算连通域数量（用作测试预言机）
  /// 使用 BFS 4-连通性
  int countConnectedComponents(List<List<bool>> mask) {
    if (mask.isEmpty || mask[0].isEmpty) return 0;
    final height = mask.length;
    final width = mask[0].length;
    final visited = List.generate(
      height,
      (_) => List.filled(width, false),
    );
    var count = 0;
    const dx = [0, 0, -1, 1];
    const dy = [-1, 1, 0, 0];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!mask[y][x] || visited[y][x]) continue;
        count++;
        // BFS
        final queue = <List<int>>[
          [x, y],
        ];
        visited[y][x] = true;
        while (queue.isNotEmpty) {
          final p = queue.removeAt(0);
          for (var d = 0; d < 4; d++) {
            final nx = p[0] + dx[d];
            final ny = p[1] + dy[d];
            if (nx >= 0 &&
                nx < width &&
                ny >= 0 &&
                ny < height &&
                mask[ny][nx] &&
                !visited[ny][nx]) {
              visited[ny][nx] = true;
              queue.add([nx, ny]);
            }
          }
        }
      }
    }
    return count;
  }

  group('CrackIdentifierService', () {
    group('labelConnectedComponents', () {
      test('空掩膜应返回空标签矩阵', () {
        final labels = service.labelConnectedComponents([]);
        expect(labels, isEmpty);
      });

      test('全黑掩膜（无裂缝）应返回全零标签矩阵', () {
        final mask = maskFromPattern([
          '...',
          '...',
          '...',
        ]);

        final labels = service.labelConnectedComponents(mask);

        for (final row in labels) {
          for (final label in row) {
            expect(label, equals(0));
          }
        }
      });

      test('单个连通域应标记为同一标签', () {
        final mask = maskFromPattern([
          '.#.',
          '.#.',
          '.#.',
        ]);

        final labels = service.labelConnectedComponents(mask);

        expect(labels[0][1], equals(1));
        expect(labels[1][1], equals(1));
        expect(labels[2][1], equals(1));
        // 非裂缝像素应为 0
        expect(labels[0][0], equals(0));
        expect(labels[0][2], equals(0));
      });

      test('两个不相连的连通域应标记为不同标签', () {
        final mask = maskFromPattern([
          '#..',
          '...',
          '..#',
        ]);

        final labels = service.labelConnectedComponents(mask);

        expect(labels[0][0], greaterThan(0));
        expect(labels[2][2], greaterThan(0));
        expect(labels[0][0], isNot(equals(labels[2][2])));
      });

      test('4-连通性：对角线像素不应连通', () {
        final mask = maskFromPattern([
          '#..',
          '.#.',
          '..#',
        ]);

        final labels = service.labelConnectedComponents(mask);

        // 对角线上的三个像素应为三个不同的连通域
        final label1 = labels[0][0];
        final label2 = labels[1][1];
        final label3 = labels[2][2];

        expect(label1, greaterThan(0));
        expect(label2, greaterThan(0));
        expect(label3, greaterThan(0));
        expect(label1, isNot(equals(label2)));
        expect(label2, isNot(equals(label3)));
        expect(label1, isNot(equals(label3)));
      });

      test('L形连通域应标记为同一标签', () {
        final mask = maskFromPattern([
          '#..',
          '#..',
          '##.',
        ]);

        final labels = service.labelConnectedComponents(mask);

        final label = labels[0][0];
        expect(label, greaterThan(0));
        expect(labels[1][0], equals(label));
        expect(labels[2][0], equals(label));
        expect(labels[2][1], equals(label));
      });

      test('全白掩膜应标记为单个连通域', () {
        final mask = maskFromPattern([
          '##',
          '##',
        ]);

        final labels = service.labelConnectedComponents(mask);

        expect(labels[0][0], equals(1));
        expect(labels[0][1], equals(1));
        expect(labels[1][0], equals(1));
        expect(labels[1][1], equals(1));
      });

      test('单个像素应标记为一个连通域', () {
        final mask = maskFromPattern([
          '...',
          '.#.',
          '...',
        ]);

        final labels = service.labelConnectedComponents(mask);

        expect(labels[1][1], equals(1));
        // 其他像素应为 0
        expect(labels[0][0], equals(0));
        expect(labels[0][1], equals(0));
        expect(labels[0][2], equals(0));
      });
    });

    group('measureCrackLength', () {
      test('空掩膜应返回 0', () {
        final length = service.measureCrackLength([]);
        expect(length, equals(0));
      });

      test('单个像素应返回长度 1', () {
        final mask = maskFromPattern(['#']);
        final length = service.measureCrackLength(mask);
        expect(length, equals(1));
      });

      test('水平线段的长度应约为像素数', () {
        // 水平线段 '#####'
        // 所有像素都是边界像素（上下都没有邻居）
        // 边界像素数 = 5, 长度 = 5/2 = 3 (rounded)
        final mask = maskFromPattern(['#####']);
        final length = service.measureCrackLength(mask);
        expect(length, equals(3)); // 5 boundary pixels / 2 = 2.5 → 3
      });

      test('垂直线段的长度应约为像素数', () {
        final mask = maskFromPattern([
          '#',
          '#',
          '#',
          '#',
          '#',
        ]);
        final length = service.measureCrackLength(mask);
        expect(length, equals(3)); // 5 boundary pixels / 2 = 2.5 → 3
      });

      test('2x2方块的边界像素数为4', () {
        final mask = maskFromPattern([
          '##',
          '##',
        ]);
        final length = service.measureCrackLength(mask);
        // 所有4个像素都是边界像素（每个都有至少一个非裂缝邻居在边界外）
        expect(length, equals(2)); // 4 boundary pixels / 2 = 2
      });

      test('3x3方块中心像素不是边界像素', () {
        final mask = maskFromPattern([
          '###',
          '###',
          '###',
        ]);
        final length = service.measureCrackLength(mask);
        // 中心像素(1,1)的4个邻居都是裂缝像素，不是边界像素
        // 边界像素 = 8 (外圈), 长度 = 8/2 = 4
        expect(length, equals(4));
      });
    });

    group('identifyCracks', () {
      test('空掩膜应返回空结果', () {
        final result = service.identifyCracks(
          crackMask: [],
          pixelRatio: 0.1,
        );

        expect(result.cracks, isEmpty);
        expect(result.totalLengthCm, equals(0));
        expect(result.averageLengthCm, equals(0));
      });

      test('全黑掩膜应返回空结果', () {
        final mask = maskFromPattern([
          '...',
          '...',
          '...',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 0.1,
        );

        expect(result.cracks, isEmpty);
        expect(result.totalLengthCm, equals(0));
        expect(result.averageLengthCm, equals(0));
      });

      test('单条裂缝应正确识别', () {
        final mask = maskFromPattern([
          '...',
          '###',
          '...',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(result.cracks.length, equals(1));
        expect(result.cracks[0].id, equals(1));
        expect(result.cracks[0].lengthPixels, greaterThan(0));
        expect(result.cracks[0].lengthCm, greaterThan(0));
      });

      test('两条独立裂缝应分别识别', () {
        final mask = maskFromPattern([
          '##...',
          '.....',
          '...##',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(result.cracks.length, equals(2));
      });

      test('裂缝应按长度降序排列', () {
        // 第一条裂缝较短（2像素），第二条较长（5像素）
        final mask = maskFromPattern([
          '##...',
          '.....',
          '#####',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(result.cracks.length, equals(2));
        expect(
          result.cracks[0].lengthCm,
          greaterThanOrEqualTo(result.cracks[1].lengthCm),
        );
      });

      test('像素比例应正确应用于长度转换', () {
        final mask = maskFromPattern([
          '#####',
        ]);

        const pixelRatio = 0.5; // 0.5 cm/像素
        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: pixelRatio,
        );

        expect(result.cracks.length, equals(1));
        final crack = result.cracks[0];
        // lengthCm = lengthPixels * pixelRatio
        expect(
          crack.lengthCm,
          closeTo(crack.lengthPixels * pixelRatio, 0.001),
        );
      });

      test('边界框应正确计算', () {
        final mask = maskFromPattern([
          '.....',
          '.###.',
          '.#.#.',
          '.###.',
          '.....',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(result.cracks.length, equals(1));
        final crack = result.cracks[0];
        expect(crack.x, equals(1));
        expect(crack.y, equals(1));
        expect(crack.w, equals(3));
        expect(crack.h, equals(3));
      });

      test('总长度应等于所有裂缝长度之和', () {
        final mask = maskFromPattern([
          '##...',
          '.....',
          '#####',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        final expectedTotal = result.cracks.fold<double>(
          0,
          (sum, crack) => sum + crack.lengthCm,
        );
        expect(result.totalLengthCm, closeTo(expectedTotal, 0.001));
      });

      test('平均长度应等于总长度除以裂缝数量', () {
        final mask = maskFromPattern([
          '##...',
          '.....',
          '#####',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        final expectedAverage = result.totalLengthCm / result.cracks.length;
        expect(result.averageLengthCm, closeTo(expectedAverage, 0.001));
      });

      test('裂缝 ID 应按排序后顺序从 1 开始递增', () {
        final mask = maskFromPattern([
          '##...',
          '.....',
          '#####',
          '.....',
          '###..',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        for (var i = 0; i < result.cracks.length; i++) {
          expect(result.cracks[i].id, equals(i + 1));
        }
      });

      test('连通域过多时应仅保留最大的 500 个', () {
        // 创建一个大掩膜，每隔一列放一个单像素裂缝
        // 这样可以创建超过 500 个连通域
        const width = 1100;
        const height = 1;
        final mask = List.generate(
          height,
          (_) => List.generate(width, (x) => x.isEven),
        );
        // 这会产生 550 个单像素连通域

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(
          result.cracks.length,
          lessThanOrEqualTo(CrackIdentifierService.maxComponents),
        );
      });

      test('宽度为零的掩膜应返回空结果', () {
        final mask = <List<bool>>[[]];

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(result.cracks, isEmpty);
        expect(result.totalLengthCm, equals(0));
        expect(result.averageLengthCm, equals(0));
      });

      test('边界框宽高应为正数', () {
        final mask = maskFromPattern([
          '.#.',
          '...',
          '#.#',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        for (final crack in result.cracks) {
          expect(crack.w, greaterThan(0));
          expect(crack.h, greaterThan(0));
        }
      });

      test('像素长度应为正数', () {
        final mask = maskFromPattern([
          '#.#',
          '...',
          '.#.',
        ]);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        for (final crack in result.cracks) {
          expect(crack.lengthPixels, greaterThan(0));
        }
      });
    });
  });

  group('CrackIdentifierService - Property 17: 裂缝识别数量与连通域一致性', () {
    // Feature: jci-calculation, Property 17: 裂缝识别数量与连通域一致性
    // **Validates: Requirements 12.1-12.6**
    //
    // 对于任意二值化裂缝掩膜，CrackIdentifierService 识别出的裂缝数量
    // 应等于掩膜中连通域的数量（当连通域数量 ≤ 500 时）。

    test('属性测试: 随机掩膜裂缝数量与连通域数量一致 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final width = random.nextInt(21) + 10; // 10-30
        final height = random.nextInt(21) + 10; // 10-30
        final density = random.nextDouble() * 0.4; // 0-0.4 density

        final mask = generateRandomMask(random, width, height, density);
        final expectedCount = countConnectedComponents(mask);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        // 当连通域数量 ≤ 500 时，裂缝数量应完全一致
        if (expectedCount <= CrackIdentifierService.maxComponents) {
          expect(
            result.cracks.length,
            equals(expectedCount),
            reason:
                '迭代 $i: ${width}x$height 掩膜 (密度=$density) '
                '期望 $expectedCount 个连通域，'
                '实际识别 ${result.cracks.length} 条裂缝',
          );
        } else {
          expect(
            result.cracks.length,
            equals(CrackIdentifierService.maxComponents),
            reason:
                '迭代 $i: 连通域数量 $expectedCount > 500，'
                '应截断为 500',
          );
        }
      }
    });

    test('属性测试: 空掩膜和全黑掩膜应返回 0 条裂缝', () {
      final random = Random(123);

      for (var i = 0; i < 20; i++) {
        final width = random.nextInt(21) + 10;
        final height = random.nextInt(21) + 10;
        // 全黑掩膜（密度 = 0）
        final mask = generateRandomMask(random, width, height, 0);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(
          result.cracks.length,
          equals(0),
          reason: '全黑掩膜应返回 0 条裂缝',
        );
      }
    });
  });

  group('CrackIdentifierService - Property 18: 裂缝度量有效性', () {
    // Feature: jci-calculation, Property 18: 裂缝度量有效性
    // **Validates: Requirements 12.1-12.6**
    //
    // 对于任意识别出的裂缝，像素长度应为正数且不超过图像对角线长度，
    // 边界框应完全在图像范围内且宽高为正数。

    test('属性测试: 随机掩膜裂缝度量有效性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final width = random.nextInt(21) + 10; // 10-30
        final height = random.nextInt(21) + 10; // 10-30
        final density = random.nextDouble() * 0.3 + 0.05; // 0.05-0.35
        final pixelRatio = random.nextDouble() * 2 + 0.1; // 0.1-2.1

        final mask = generateRandomMask(random, width, height, density);
        final diagonal = sqrt(width * width + height * height);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: pixelRatio,
        );

        for (final crack in result.cracks) {
          // 像素长度应为正数
          expect(
            crack.lengthPixels,
            greaterThan(0),
            reason:
                '迭代 $i: 裂缝 ${crack.id} 像素长度应为正数，'
                '实际为 ${crack.lengthPixels}',
          );

          // 像素长度不应超过图像对角线长度
          expect(
            crack.lengthPixels.toDouble(),
            lessThanOrEqualTo(diagonal),
            reason:
                '迭代 $i: 裂缝 ${crack.id} 像素长度 ${crack.lengthPixels} '
                '不应超过对角线长度 $diagonal',
          );

          // 边界框宽高应为正数
          expect(
            crack.w,
            greaterThan(0),
            reason: '迭代 $i: 裂缝 ${crack.id} 边界框宽度应为正数',
          );
          expect(
            crack.h,
            greaterThan(0),
            reason: '迭代 $i: 裂缝 ${crack.id} 边界框高度应为正数',
          );

          // 边界框应完全在图像范围内
          expect(
            crack.x,
            greaterThanOrEqualTo(0),
            reason: '迭代 $i: 裂缝 ${crack.id} x 应 >= 0',
          );
          expect(
            crack.y,
            greaterThanOrEqualTo(0),
            reason: '迭代 $i: 裂缝 ${crack.id} y 应 >= 0',
          );
          expect(
            crack.x + crack.w,
            lessThanOrEqualTo(width),
            reason:
                '迭代 $i: 裂缝 ${crack.id} x+w=${crack.x + crack.w} '
                '应 <= 图像宽度 $width',
          );
          expect(
            crack.y + crack.h,
            lessThanOrEqualTo(height),
            reason:
                '迭代 $i: 裂缝 ${crack.id} y+h=${crack.y + crack.h} '
                '应 <= 图像高度 $height',
          );
        }
      }
    });
  });

  group('CrackIdentifierService - Property 19: 裂缝列表排序正确性', () {
    // Feature: jci-calculation, Property 19: 裂缝列表排序正确性
    // **Validates: Requirements 12.1-12.6**
    //
    // 对于任意裂缝识别结果，输出的裂缝列表应按长度从大到小排序
    // （即对于列表中相邻的两条裂缝，前者长度应大于等于后者长度）。

    test('属性测试: 随机掩膜裂缝列表按长度降序排列 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final width = random.nextInt(21) + 10; // 10-30
        final height = random.nextInt(21) + 10; // 10-30
        final density = random.nextDouble() * 0.3 + 0.05; // 0.05-0.35

        final mask = generateRandomMask(random, width, height, density);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        // 验证相邻裂缝的长度关系
        for (var j = 0; j < result.cracks.length - 1; j++) {
          expect(
            result.cracks[j].lengthCm,
            greaterThanOrEqualTo(result.cracks[j + 1].lengthCm),
            reason:
                '迭代 $i: 裂缝 ${j + 1} (长度=${result.cracks[j].lengthCm}) '
                '应 >= 裂缝 ${j + 2} (长度=${result.cracks[j + 1].lengthCm})',
          );
        }
      }
    });

    test('属性测试: 不同像素比例下排序仍然正确 (50 次迭代)', () {
      final random = Random(99);

      for (var i = 0; i < 50; i++) {
        final width = random.nextInt(21) + 10;
        final height = random.nextInt(21) + 10;
        final density = random.nextDouble() * 0.3 + 0.05;
        final pixelRatio = random.nextDouble() * 5 + 0.01; // 0.01-5.01

        final mask = generateRandomMask(random, width, height, density);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: pixelRatio,
        );

        for (var j = 0; j < result.cracks.length - 1; j++) {
          expect(
            result.cracks[j].lengthCm,
            greaterThanOrEqualTo(result.cracks[j + 1].lengthCm),
            reason:
                '迭代 $i (pixelRatio=$pixelRatio): '
                '裂缝 ${j + 1} 长度应 >= 裂缝 ${j + 2} 长度',
          );
        }
      }
    });
  });

  group('CrackIdentifierService - Property 20: 裂缝总长度与平均长度一致性', () {
    // Feature: jci-calculation, Property 20: 裂缝总长度与平均长度一致性
    // **Validates: Requirements 12.1-12.6**
    //
    // 对于任意非空裂缝列表，totalLengthCm 应等于所有裂缝 lengthCm 之和，
    // averageLengthCm 应等于 totalLengthCm 除以裂缝数量。

    test('属性测试: 随机掩膜总长度与平均长度一致性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final width = random.nextInt(21) + 10; // 10-30
        final height = random.nextInt(21) + 10; // 10-30
        final density = random.nextDouble() * 0.3 + 0.05; // 0.05-0.35
        final pixelRatio = random.nextDouble() * 2 + 0.1; // 0.1-2.1

        final mask = generateRandomMask(random, width, height, density);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: pixelRatio,
        );

        if (result.cracks.isEmpty) continue;

        // totalLengthCm 应等于所有裂缝 lengthCm 之和
        final expectedTotal = result.cracks.fold<double>(
          0,
          (sum, crack) => sum + crack.lengthCm,
        );
        expect(
          result.totalLengthCm,
          closeTo(expectedTotal, 0.001),
          reason:
              '迭代 $i: totalLengthCm=${result.totalLengthCm} '
              '应等于各裂缝长度之和=$expectedTotal',
        );

        // averageLengthCm 应等于 totalLengthCm / 裂缝数量
        final expectedAverage = result.totalLengthCm / result.cracks.length;
        expect(
          result.averageLengthCm,
          closeTo(expectedAverage, 0.001),
          reason:
              '迭代 $i: averageLengthCm=${result.averageLengthCm} '
              '应等于 totalLengthCm/count=$expectedAverage',
        );
      }
    });

    test('属性测试: 空掩膜总长度和平均长度均为 0', () {
      final random = Random(77);

      for (var i = 0; i < 20; i++) {
        final width = random.nextInt(21) + 10;
        final height = random.nextInt(21) + 10;
        final mask = generateRandomMask(random, width, height, 0);

        final result = service.identifyCracks(
          crackMask: mask,
          pixelRatio: 1,
        );

        expect(result.totalLengthCm, equals(0));
        expect(result.averageLengthCm, equals(0));
      }
    });
  });
}
