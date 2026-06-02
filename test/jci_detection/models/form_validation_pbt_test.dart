import 'dart:math';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/form_validation_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Property 4: 表单验证完整性', () {
    // Feature: jci-calculation, Property 4: 表单验证完整性
    // **Validates: Requirements 3.7, 3.8**
    //
    // 对于任意表单输入状态：
    // - 当任一必填项（岩石种类、工程埋深、地下水状况）为空时，表单验证应失败
    // - 当埋深值为非正数时，表单验证应失败
    // - 当所有必填项都已填写且埋深为正数时，表单验证应通过

    /// 生成随机的可空岩石种类
    RockType? randomRockType(Random random) {
      if (random.nextInt(3) == 0) return null; // ~33% chance null
      return RockType.values[random.nextInt(RockType.values.length)];
    }

    /// 生成随机的可空地下水状况
    WaterCondition? randomWaterCondition(Random random) {
      if (random.nextInt(3) == 0) return null; // ~33% chance null
      return WaterCondition.values[random.nextInt(
        WaterCondition.values.length,
      )];
    }

    /// 生成随机的埋深文本输入
    ///
    /// 包含各种情况：null、空字符串、非数字、零、负数、正数
    String? randomDepthText(Random random) {
      final choice = random.nextInt(7);
      switch (choice) {
        case 0:
          return null;
        case 1:
          return '';
        case 2:
          return 'abc'; // 非数字
        case 3:
          return '0'; // 零
        case 4:
          return '-${(random.nextDouble() * 1000).toStringAsFixed(2)}'; // 负数
        case 5:
          return (random.nextDouble() * 2000 + 0.01).toStringAsFixed(2); // 正数
        case 6:
          return '${random.nextInt(3000) + 1}'; // 正整数
        default:
          return null;
      }
    }

    /// 判断埋深文本是否表示有效的正数
    bool isDepthTextValid(String? text) {
      if (text == null || text.isEmpty) return false;
      final depth = double.tryParse(text);
      if (depth == null) return false;
      return depth > 0;
    }

    test('属性测试: 表单验证完整性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final rockType = randomRockType(random);
        final depthText = randomDepthText(random);
        final waterCondition = randomWaterCondition(random);

        final state = FormValidationState.fromInputs(
          rockType: rockType,
          depthText: depthText,
          waterCondition: waterCondition,
        );

        final rockValid = rockType != null;
        final depthValid = isDepthTextValid(depthText);
        final waterValid = waterCondition != null;
        final expectedValid = rockValid && depthValid && waterValid;

        // 验证各字段验证状态
        expect(
          state.isRockTypeValid,
          equals(rockValid),
          reason:
              '迭代 $i: rockType=${rockType?.displayName ?? "null"} → '
              'isRockTypeValid 应为 $rockValid',
        );

        expect(
          state.isDepthValid,
          equals(depthValid),
          reason:
              '迭代 $i: depthText=${depthText ?? "null"} → '
              'isDepthValid 应为 $depthValid',
        );

        final waterConditionName = waterCondition?.displayName ?? 'null';
        expect(
          state.isWaterConditionValid,
          equals(waterValid),
          reason:
              '迭代 $i: waterCondition=$waterConditionName → '
              'isWaterConditionValid 应为 $waterValid',
        );

        // 验证整体验证状态
        expect(
          state.isValid,
          equals(expectedValid),
          reason:
              '迭代 $i: rockType=${rockType?.displayName ?? "null"}, '
              'depthText=${depthText ?? "null"}, '
              'waterCondition=${waterCondition?.displayName ?? "null"} → '
              'isValid 应为 $expectedValid',
        );

        // 当任一必填项为空时，验证应失败
        if (!rockValid || !depthValid || !waterValid) {
          expect(
            state.isValid,
            isFalse,
            reason: '迭代 $i: 存在无效必填项，表单验证应失败',
          );
          expect(
            state.errors,
            isNotEmpty,
            reason: '迭代 $i: 验证失败时应有错误信息',
          );
        }

        // 当所有必填项都有效时，验证应通过
        if (rockValid && depthValid && waterValid) {
          expect(
            state.isValid,
            isTrue,
            reason: '迭代 $i: 所有必填项有效，表单验证应通过',
          );
          expect(
            state.errors,
            isEmpty,
            reason: '迭代 $i: 验证通过时不应有错误信息',
          );
        }
      }
    });

    test('属性测试: 非正数埋深始终导致验证失败 (100 次迭代)', () {
      final random = Random(99);

      for (var i = 0; i < 100; i++) {
        // 生成非正数埋深
        final nonPositiveDepth = switch (random.nextInt(3)) {
          0 => '0',
          1 => '-${(random.nextDouble() * 1000).toStringAsFixed(2)}',
          _ => '-${random.nextInt(1000) + 1}',
        };

        final state = FormValidationState.fromInputs(
          rockType: RockType.values[random.nextInt(RockType.values.length)],
          depthText: nonPositiveDepth,
          waterCondition: WaterCondition
              .values[random.nextInt(WaterCondition.values.length)],
        );

        expect(
          state.isDepthValid,
          isFalse,
          reason: '迭代 $i: 非正数埋深 "$nonPositiveDepth" 应导致验证失败',
        );
        expect(
          state.isValid,
          isFalse,
          reason: '迭代 $i: 非正数埋深应导致整体验证失败',
        );
      }
    });

    test('属性测试: 所有必填项有效且埋深为正数时验证通过 (100 次迭代)', () {
      final random = Random(77);

      for (var i = 0; i < 100; i++) {
        final rockType =
            RockType.values[random.nextInt(RockType.values.length)];
        final positiveDepth = (random.nextDouble() * 2000 + 0.01)
            .toStringAsFixed(2);
        final waterCondition =
            WaterCondition.values[random.nextInt(WaterCondition.values.length)];

        final state = FormValidationState.fromInputs(
          rockType: rockType,
          depthText: positiveDepth,
          waterCondition: waterCondition,
        );

        expect(
          state.isRockTypeValid,
          isTrue,
          reason: '迭代 $i: 岩石种类 ${rockType.displayName} 应有效',
        );
        expect(
          state.isDepthValid,
          isTrue,
          reason: '迭代 $i: 正数埋深 "$positiveDepth" 应有效',
        );
        expect(
          state.isWaterConditionValid,
          isTrue,
          reason: '迭代 $i: 地下水状况 ${waterCondition.displayName} 应有效',
        );
        expect(
          state.isValid,
          isTrue,
          reason: '迭代 $i: 所有必填项有效，表单验证应通过',
        );
        expect(
          state.errors,
          isEmpty,
          reason: '迭代 $i: 验证通过时不应有错误信息',
        );
      }
    });
  });
}
