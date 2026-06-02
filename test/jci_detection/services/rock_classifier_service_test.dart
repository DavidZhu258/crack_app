// Property-test reason strings are split without added whitespace so the
// rendered failure message stays natural in Chinese.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/services/rock_classifier_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RockClassifierService service;

  setUp(() {
    service = RockClassifierService();
  });

  group('RockClassifierService - Property 1: 围岩等级分类正确性', () {
    // Feature: jci-calculation, Property 1: 围岩等级分类正确性
    // **Validates: Requirements 5.1-5.7**
    //
    // 对于任意 JCI 值，classify() 的分类结果应满足：
    // - JCI > 40 → I-1
    // - 35 ≤ JCI ≤ 40 → I-2
    // - 30 ≤ JCI < 35 → II-1
    // - 24 ≤ JCI < 30 → II-2
    // - 22 ≤ JCI < 24 → III
    // - 16 ≤ JCI < 22 → IV
    // - JCI < 16 → V

    /// 根据 JCI 值返回期望的围岩等级（作为测试预言机）
    RockGrade expectedGrade(double jci) {
      if (jci > 40) return RockGrade.i1;
      if (jci >= 35) return RockGrade.i2;
      if (jci >= 30) return RockGrade.ii1;
      if (jci >= 24) return RockGrade.ii2;
      if (jci >= 22) return RockGrade.iii;
      if (jci >= 16) return RockGrade.iv;
      return RockGrade.v;
    }

    test('属性测试: 随机 JCI 值分类正确性 (100 次迭代)', () {
      final random = Random(42); // 固定种子保证可重现

      for (var i = 0; i < 100; i++) {
        // 生成 -100 到 200 范围内的随机 double
        final jci = random.nextDouble() * 300 - 100;

        final result = service.classify(jci);
        final expected = expectedGrade(jci);

        expect(
          result,
          equals(expected),
          reason:
              'JCI=$jci 应分类为 ${expected.fullName}，'
              '但实际为 ${result.fullName}',
        );
      }
    });

    test('属性测试: 边界值附近的分类正确性', () {
      // 在每个边界值附近生成密集的测试点
      const boundaries = [16.0, 22.0, 24.0, 30.0, 35.0, 40.0];
      const offsets = [-0.01, 0.0, 0.01, -0.001, 0.001, -1.0, 1.0];

      for (final boundary in boundaries) {
        for (final offset in offsets) {
          final jci = boundary + offset;
          final result = service.classify(jci);
          final expected = expectedGrade(jci);

          expect(
            result,
            equals(expected),
            reason:
                'JCI=$jci (边界 $boundary + 偏移 $offset) '
                '应分类为 ${expected.fullName}，'
                '但实际为 ${result.fullName}',
          );
        }
      }
    });

    test('属性测试: 极端值分类正确性', () {
      final extremeValues = [
        -100.0,
        -1000.0,
        0.0,
        200.0,
        1000.0,
        double.maxFinite,
        -double.maxFinite,
      ];

      for (final jci in extremeValues) {
        final result = service.classify(jci);
        final expected = expectedGrade(jci);

        expect(
          result,
          equals(expected),
          reason:
              'JCI=$jci 应分类为 ${expected.fullName}，'
              '但实际为 ${result.fullName}',
        );
      }
    });
  });

  group('RockClassifierService - Property 2: 渗水降级正确性', () {
    // Feature: jci-calculation, Property 2: 渗水降级正确性
    // **Validates: Requirements 6.2, 6.3**
    //
    // 对于任意围岩等级和渗水状态组合：
    // - 当存在渗水且原等级不是 Ⅳ级时，最终等级应比原等级低一级
    // - 当存在渗水且原等级是 Ⅳ级时，最终等级保持 Ⅳ级
    // - 当不存在渗水时，最终等级等于原等级

    /// 等级降序列表，用于验证"低一级"关系
    final gradeOrder = [
      RockGrade.i1,
      RockGrade.i2,
      RockGrade.ii1,
      RockGrade.ii2,
      RockGrade.iii,
      RockGrade.iv,
      RockGrade.v,
    ];

    /// 返回给定等级降低一级后的期望等级
    RockGrade expectedDowngrade(RockGrade grade) {
      final index = gradeOrder.indexOf(grade);
      if (index == gradeOrder.length - 1) return grade; // V级保持不变
      return gradeOrder[index + 1];
    }

    test('属性测试: 所有等级 × 渗水状态组合的降级正确性', () {
      for (final grade in RockGrade.values) {
        for (final hasSeepage in [true, false]) {
          final result = service.applySeepageAdjustment(
            grade,
            hasSeepage: hasSeepage,
          );

          // 原等级应始终正确记录
          expect(
            result.originalGrade,
            equals(grade),
            reason: '原等级应为 ${grade.fullName}',
          );

          if (!hasSeepage) {
            // 不存在渗水时，最终等级等于原等级
            expect(
              result.finalGrade,
              equals(grade),
              reason:
                  '无渗水时，${grade.fullName} 应保持不变，'
                  '但实际为 ${result.finalGrade.fullName}',
            );
            expect(
              result.wasDowngraded,
              isFalse,
              reason: '无渗水时不应标记为降级',
            );
          } else if (grade == RockGrade.v) {
            // 存在渗水且原等级是 V 级时，保持 V 级
            expect(
              result.finalGrade,
              equals(RockGrade.v),
              reason: '渗水时 V 级应保持 V 级不变',
            );
          } else {
            // 存在渗水且原等级不是 Ⅳ级时，降低一级
            final expected = expectedDowngrade(grade);
            expect(
              result.finalGrade,
              equals(expected),
              reason:
                  '渗水时 ${grade.fullName} 应降为 ${expected.fullName}，'
                  '但实际为 ${result.finalGrade.fullName}',
            );
            expect(
              result.wasDowngraded,
              isTrue,
              reason: '渗水降级时应标记 wasDowngraded 为 true',
            );
          }
        }
      }
    });

    test('属性测试: downgradeOneLevel 等级链正确性', () {
      // 验证降级链: i1 → i2 → ii1 → ii2 → iii → iv → v → v
      for (var i = 0; i < gradeOrder.length; i++) {
        final grade = gradeOrder[i];
        final result = service.downgradeOneLevel(grade);
        final expected = expectedDowngrade(grade);

        expect(
          result,
          equals(expected),
          reason:
              '${grade.fullName} 降一级应为 ${expected.fullName}，'
              '但实际为 ${result.fullName}',
        );
      }
    });

    test('属性测试: 渗水降级后等级索引恰好增加1（Ⅳ级除外）', () {
      for (final grade in RockGrade.values) {
        if (grade == RockGrade.v) continue;

        final result = service.applySeepageAdjustment(
          grade,
          hasSeepage: true,
        );

        final originalIndex = gradeOrder.indexOf(grade);
        final finalIndex = gradeOrder.indexOf(result.finalGrade);

        expect(
          finalIndex - originalIndex,
          equals(1),
          reason:
              '${grade.fullName}(索引$originalIndex) 渗水降级后应为索引'
              '${originalIndex + 1}，但实际为索引$finalIndex',
        );
      }
    });
  });

  group('RockClassifierService - 软件改动等级显示', () {
    test('围岩等级显示名称应使用 I-1/I-2/II-1/II-2/III/IV/V', () {
      expect(
        RockGrade.values.map((grade) => grade.name).toList(),
        equals(['I-1', 'I-2', 'II-1', 'II-2', 'III', 'IV', 'V']),
      );
    });

    test('围岩等级描述应与软件改动表一致', () {
      expect(
        RockGrade.values.map((grade) => grade.description).toList(),
        equals(['极好', '好', '较好', '一般', '较差', '差', '极差']),
      );
    });
  });
}
