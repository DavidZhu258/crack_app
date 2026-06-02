// Property-test reason strings are split without added whitespace so the
// rendered failure message stays natural in Chinese.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:crack_app/jci_detection/cubit/jci_detection_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Property 3: 图像数量与按钮状态一致性', () {
    // Feature: jci-calculation, Property 3: 图像数量与按钮状态一致性
    // **Validates: Requirements 1.4, 1.5**
    //
    // 对于任意图像选择状态：
    // - 当第一张识别图像已选择时，"开始分析"按钮应启用（canStartAnalysis == true）
    // - 当未选择识别图像时，尝试提交应被阻止（canStartAnalysis == false）

    /// 生成随机的可空图像路径
    String? randomImagePath(Random random) {
      // ~50% chance of being null
      if (random.nextBool()) return null;
      return '/path/to/image_${random.nextInt(10000)}.jpg';
    }

    test('属性测试: canStartAnalysis 当且仅当识别图像已选择 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final image1Path = randomImagePath(random);
        final image2Path = randomImagePath(random);

        final state = JciDetectionImagesSelected(
          image1Path: image1Path,
          image2Path: image2Path,
        );

        final recognitionImageSelected = image1Path != null;

        expect(
          state.canStartAnalysis,
          equals(recognitionImageSelected),
          reason:
              '迭代 $i: image1Path=${image1Path ?? "null"}, '
              'image2Path=${image2Path ?? "null"} → '
              'canStartAnalysis 应为 $recognitionImageSelected，'
              '但实际为 ${state.canStartAnalysis}',
        );

        // Also verify selectedImageCount is consistent
        final expectedCount =
            (image1Path != null ? 1 : 0) + (image2Path != null ? 1 : 0);
        expect(
          state.selectedImageCount,
          equals(expectedCount),
          reason:
              '迭代 $i: selectedImageCount 应为 $expectedCount，'
              '但实际为 ${state.selectedImageCount}',
        );

        // When no recognition image is selected, submission should be blocked
        if (image1Path == null) {
          expect(
            state.canStartAnalysis,
            isFalse,
            reason: '迭代 $i: 未选择识别图像，提交应被阻止',
          );
        }
      }
    });

    test('属性测试: 所有四种组合的穷举验证', () {
      // Exhaustively test all 4 combinations of null/non-null
      final combinations = <(String?, String?)>[
        (null, null),
        (null, '/path/image2.jpg'),
        ('/path/image1.jpg', null),
        ('/path/image1.jpg', '/path/image2.jpg'),
      ];

      for (final (img1, img2) in combinations) {
        final state = JciDetectionImagesSelected(
          image1Path: img1,
          image2Path: img2,
        );

        final recognitionImageSelected = img1 != null;

        expect(
          state.canStartAnalysis,
          equals(recognitionImageSelected),
          reason:
              'image1=${img1 ?? "null"}, image2=${img2 ?? "null"} → '
              'canStartAnalysis 应为 $recognitionImageSelected',
        );
      }
    });

    test('属性测试: hasImage1/hasImage2 与路径一致性 (100 次迭代)', () {
      final random = Random(123);

      for (var i = 0; i < 100; i++) {
        final image1Path = randomImagePath(random);
        final image2Path = randomImagePath(random);

        final state = JciDetectionImagesSelected(
          image1Path: image1Path,
          image2Path: image2Path,
        );

        expect(
          state.hasImage1,
          equals(image1Path != null),
          reason: '迭代 $i: hasImage1 应与 image1Path 非空一致',
        );
        expect(
          state.hasImage2,
          equals(image2Path != null),
          reason: '迭代 $i: hasImage2 应与 image2Path 非空一致',
        );

        // canStartAnalysis iff the recognition image has been selected.
        expect(
          state.canStartAnalysis,
          equals(state.hasImage1),
          reason: '迭代 $i: canStartAnalysis 应等于 hasImage1',
        );
      }
    });
  });
}
