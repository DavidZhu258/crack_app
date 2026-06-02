// Property-test reason strings are split without added whitespace so the
// rendered failure message stays natural in Chinese.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late JciCalculatorService service;

  setUp(() {
    service = JciCalculatorService();
  });

  group('JciCalculatorService - Property 5: JCI 计算确定性', () {
    // Feature: jci-calculation, Property 5: JCI 计算确定性
    // **Validates: Requirements 4.1**

    JciInputParameters randomParams(Random random) {
      return JciInputParameters(
        indicator1: random.nextDouble() * 5,
        indicator2: random.nextDouble() * 300,
        indicator3: random.nextDouble() * 3,
        depth: random.nextDouble() * 2000,
      );
    }

    test('属性测试: 相同输入产生相同 JCI 值 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final params = randomParams(random);

        final result1 = service.calculate(params);
        final result2 = service.calculate(params);

        expect(
          result1.jciValue,
          equals(result2.jciValue),
          reason:
              '迭代 $i: 相同输入应产生相同的 JCI 值，'
              '但得到 ${result1.jciValue} 和 ${result2.jciValue}',
        );
      }
    });

    test('属性测试: 相同输入产生相同的各项得分明细 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final params = randomParams(random);

        final result1 = service.calculate(params);
        final result2 = service.calculate(params);

        expect(
          result1.componentScores,
          equals(result2.componentScores),
          reason: '迭代 $i: 相同输入应产生相同的各项得分明细',
        );
      }
    });

    test('属性测试: 不同服务实例计算相同输入也应确定性 (100 次迭代)', () {
      final random = Random(42);

      for (var i = 0; i < 100; i++) {
        final params = randomParams(random);

        final service1 = JciCalculatorService();
        final service2 = JciCalculatorService();

        final result1 = service1.calculate(params);
        final result2 = service2.calculate(params);

        expect(
          result1.jciValue,
          equals(result2.jciValue),
          reason: '迭代 $i: 不同服务实例对相同输入应产生相同的 JCI 值',
        );
      }
    });
  });

  group('JciCalculatorService - Property 5: RMR 计算公式正确性', () {
    // Feature: jci-calculation, Property 5: RMR 计算公式正确性
    // **Validates: Requirements 4.2, 4.3, 4.4**

    /// 独立的 R2 查表实现（测试预言）
    int expectedR2(double indicator3) {
      if (indicator3 >= 1.571) return 3;
      if (indicator3 >= 1.097) return 8;
      if (indicator3 >= 0.659) return 10;
      if (indicator3 >= 0.276) return 17;
      return 20;
    }

    /// 独立的 R3 查表实现（测试预言）
    int expectedR3(double indicator2) {
      if (indicator2 <= 30) return 3;
      if (indicator2 <= 50) return 8;
      if (indicator2 <= 110) return 10;
      if (indicator2 <= 200) return 17;
      return 20;
    }

    test('属性测试: R2 根据 indicator3 查表正确 (100 次迭代)', () {
      final random = Random(12345);

      for (var i = 0; i < 100; i++) {
        final indicator3 = random.nextDouble() * 5; // 0-5

        final actualR2 = service.calculateR2(indicator3);
        final expected = expectedR2(indicator3);

        expect(
          actualR2,
          equals(expected),
          reason:
              '迭代 $i: indicator3=$indicator3 时 R2 应为 $expected，'
              '但得到 $actualR2',
        );
      }
    });

    test('属性测试: R3 根据 indicator2 查表正确 (100 次迭代)', () {
      final random = Random(12345);

      for (var i = 0; i < 100; i++) {
        final indicator2 = random.nextDouble() * 500; // 0-500

        final actualR3 = service.calculateR3(indicator2);
        final expected = expectedR3(indicator2);

        expect(
          actualR3,
          equals(expected),
          reason:
              '迭代 $i: indicator2=$indicator2 时 R3 应为 $expected，'
              '但得到 $actualR3',
        );
      }
    });

    test('属性测试: RMR = 3 + R2 + R3 + 4 (100 次迭代)', () {
      final random = Random(12345);

      for (var i = 0; i < 100; i++) {
        final indicator2 = random.nextDouble() * 500; // 0-500
        final indicator3 = random.nextDouble() * 5; // 0-5

        final actualRMR = service.calculateRMR(indicator2, indicator3);
        final r2 = expectedR2(indicator3);
        final r3 = expectedR3(indicator2);
        final expectedRMR = 3.0 + r2 + r3 + 4.0;

        expect(
          actualRMR,
          equals(expectedRMR),
          reason:
              '迭代 $i: indicator2=$indicator2, indicator3=$indicator3 时 '
              'RMR 应为 $expectedRMR (3 + $r2 + $r3 + 4)，但得到 $actualRMR',
        );
      }
    });
  });

  group('JciCalculatorService - calculateR2', () {
    // Feature: jci-calculation, R2 查表
    // **Validates: Requirements 4.3**

    test('indicator3 >= 1.571 时 R2=3', () {
      expect(service.calculateR2(1.571), equals(3));
      expect(service.calculateR2(2), equals(3));
      expect(service.calculateR2(10), equals(3));
    });

    test('1.097 <= indicator3 < 1.571 时 R2=8', () {
      expect(service.calculateR2(1.097), equals(8));
      expect(service.calculateR2(1.3), equals(8));
      expect(service.calculateR2(1.570), equals(8));
    });

    test('0.659 <= indicator3 < 1.097 时 R2=10', () {
      expect(service.calculateR2(0.659), equals(10));
      expect(service.calculateR2(0.8), equals(10));
      expect(service.calculateR2(1.096), equals(10));
    });

    test('0.276 <= indicator3 < 0.659 时 R2=17', () {
      expect(service.calculateR2(0.276), equals(17));
      expect(service.calculateR2(0.4), equals(17));
      expect(service.calculateR2(0.658), equals(17));
    });

    test('indicator3 < 0.276 时 R2=20', () {
      expect(service.calculateR2(0.275), equals(20));
      expect(service.calculateR2(0.1), equals(20));
      expect(service.calculateR2(0), equals(20));
    });
  });

  group('JciCalculatorService - calculateR3', () {
    // Feature: jci-calculation, R3 查表
    // **Validates: Requirements 4.4**

    test('indicator2 <= 30 时 R3=3', () {
      expect(service.calculateR3(30), equals(3));
      expect(service.calculateR3(10), equals(3));
      expect(service.calculateR3(0), equals(3));
    });

    test('30 < indicator2 <= 50 时 R3=8', () {
      expect(service.calculateR3(31), equals(8));
      expect(service.calculateR3(40), equals(8));
      expect(service.calculateR3(50), equals(8));
    });

    test('50 < indicator2 <= 110 时 R3=10', () {
      expect(service.calculateR3(51), equals(10));
      expect(service.calculateR3(80), equals(10));
      expect(service.calculateR3(110), equals(10));
    });

    test('110 < indicator2 <= 200 时 R3=17', () {
      expect(service.calculateR3(111), equals(17));
      expect(service.calculateR3(150), equals(17));
      expect(service.calculateR3(200), equals(17));
    });

    test('indicator2 > 200 时 R3=20', () {
      expect(service.calculateR3(201), equals(20));
      expect(service.calculateR3(300), equals(20));
      expect(service.calculateR3(500), equals(20));
    });
  });

  group('JciCalculatorService - calculateRMR', () {
    // Feature: jci-calculation, RMR 计算
    // **Validates: Requirements 4.2**

    test('RMR = R1(3) + R2 + R3 + R456(4)', () {
      // indicator3=2.0 → R2=3, indicator2=10 → R3=3
      expect(service.calculateRMR(10, 2), equals(3 + 3 + 3 + 4));

      // indicator3=0.1 → R2=20, indicator2=300 → R3=20
      expect(service.calculateRMR(300, 0.1), equals(3 + 20 + 20 + 4));

      // indicator3=0.8 → R2=10, indicator2=80 → R3=10
      expect(service.calculateRMR(80, 0.8), equals(3 + 10 + 10 + 4));
    });
  });

  group('JciCalculatorService - R1/S/h(S) 新公式', () {
    test('R1 应根据 UCS 边界查表', () {
      expect(service.calculateR1(181), equals(10));
      expect(service.calculateR1(180), equals(7));
      expect(service.calculateR1(70), equals(7));
      expect(service.calculateR1(69.99), equals(3));
      expect(service.calculateR1(35), equals(3));
      expect(service.calculateR1(34.99), equals(2));
      expect(service.calculateR1(25), equals(2));
      expect(service.calculateR1(24.99), equals(1));
      expect(service.calculateR1(1), equals(1));
      expect(service.calculateR1(0.99), equals(0));
    });

    test('S = UCS / 地应力，h(S)=15×log10(S)', () {
      final s = service.calculateS(ucsMpa: 35, groundStressMpa: 7);
      expect(s, closeTo(5, 1e-12));
      expect(service.calculateHSFromS(s), closeTo(15 * log(5) / ln10, 1e-12));
    });

    test('calculate 使用 UCS 与地应力计算 R1、S、h(S) 和最终 JCI', () {
      const params = JciInputParameters(
        indicator1: 0.3,
        indicator2: 80,
        indicator3: 0.8,
        depth: 598,
        groundStressMpa: 7,
      );

      final result = service.calculate(params);

      const rmr = 3.0 + 10 + 10 + 4;
      const q = (0.5 / 9) * 0.33 * (1 / 7.5);
      final gQ = 10 * (log(q) / ln10) + 50;
      final hS = 15 * (log(5) / ln10);
      final expected = 0.0454 * rmr + 0.6586 * gQ + 0.2960 * hS;

      expect(result.rmr, closeTo(rmr, 1e-12));
      expect(result.qValue, closeTo(q, 1e-12));
      expect(result.hS, closeTo(hS, 1e-12));
      expect(result.componentScores['R1'], equals(3));
      expect(result.componentScores['S'], closeTo(5, 1e-12));
      expect(result.componentScores['groundStressMpa'], closeTo(7, 1e-12));
      expect(result.jciValue, closeTo(expected, 1e-12));
    });
  });

  group('JciCalculatorService - calculateRQDValue', () {
    // Feature: jci-calculation, RQD_value 查表
    // **Validates: Requirements 4.5**

    test('indicator3 >= 1.571 时 RQD_value=0.15', () {
      expect(service.calculateRQDValue(1.571), equals(0.15));
      expect(service.calculateRQDValue(2), equals(0.15));
      expect(service.calculateRQDValue(10), equals(0.15));
    });

    test('1.097 <= indicator3 < 1.571 时 RQD_value=0.4', () {
      expect(service.calculateRQDValue(1.097), equals(0.4));
      expect(service.calculateRQDValue(1.3), equals(0.4));
      expect(service.calculateRQDValue(1.570), equals(0.4));
    });

    test('0.659 <= indicator3 < 1.097 时 RQD_value=0.5', () {
      expect(service.calculateRQDValue(0.659), equals(0.5));
      expect(service.calculateRQDValue(0.8), equals(0.5));
      expect(service.calculateRQDValue(1.096), equals(0.5));
    });

    test('0.276 <= indicator3 < 0.659 时 RQD_value=0.85', () {
      expect(service.calculateRQDValue(0.276), equals(0.85));
      expect(service.calculateRQDValue(0.4), equals(0.85));
      expect(service.calculateRQDValue(0.658), equals(0.85));
    });

    test('indicator3 < 0.276 时 RQD_value=1.0', () {
      expect(service.calculateRQDValue(0.275), equals(1.0));
      expect(service.calculateRQDValue(0.1), equals(1.0));
      expect(service.calculateRQDValue(0), equals(1.0));
    });
  });

  group('JciCalculatorService - calculateJn', () {
    // Feature: jci-calculation, Jn 查表
    // **Validates: Requirements 4.6**

    test('indicator1 <= 0.58 时 Jn=9', () {
      expect(service.calculateJn(0), equals(9));
      expect(service.calculateJn(0.3), equals(9));
      expect(service.calculateJn(0.58), equals(9));
    });

    test('0.58 < indicator1 <= 0.91 时 Jn=6', () {
      expect(service.calculateJn(0.59), equals(6));
      expect(service.calculateJn(0.75), equals(6));
      expect(service.calculateJn(0.91), equals(6));
    });

    test('0.91 < indicator1 <= 1.18 时 Jn=4', () {
      expect(service.calculateJn(0.92), equals(4));
      expect(service.calculateJn(1), equals(4));
      expect(service.calculateJn(1.18), equals(4));
    });

    test('1.18 < indicator1 <= 1.45 时 Jn=3', () {
      expect(service.calculateJn(1.19), equals(3));
      expect(service.calculateJn(1.3), equals(3));
      expect(service.calculateJn(1.45), equals(3));
    });

    test('1.45 < indicator1 <= 1.92 时 Jn=2', () {
      expect(service.calculateJn(1.46), equals(2));
      expect(service.calculateJn(1.7), equals(2));
      expect(service.calculateJn(1.92), equals(2));
    });

    test('1.92 < indicator1 <= 2.76 时 Jn=1', () {
      expect(service.calculateJn(1.93), equals(1));
      expect(service.calculateJn(2.3), equals(1));
      expect(service.calculateJn(2.76), equals(1));
    });

    test('indicator1 > 2.76 时 Jn=0.5', () {
      expect(service.calculateJn(2.77), equals(0.5));
      expect(service.calculateJn(3), equals(0.5));
      expect(service.calculateJn(10), equals(0.5));
    });
  });

  group('JciCalculatorService - calculateSRF', () {
    // Feature: jci-calculation, SRF 计算
    // **Validates: Requirements 4.8**

    test('(1700 - h) > 600 时 SRF=7.5', () {
      // 1700 - 0 = 1700 > 600
      expect(service.calculateSRF(0), equals(7.5));
      // 1700 - 500 = 1200 > 600
      expect(service.calculateSRF(500), equals(7.5));
      // 1700 - 1099 = 601 > 600
      expect(service.calculateSRF(1099), equals(7.5));
    });

    test('(1700 - h) <= 600 时 SRF=2.5', () {
      // 1700 - 1100 = 600, 不大于600
      expect(service.calculateSRF(1100), equals(2.5));
      // 1700 - 1200 = 500 <= 600
      expect(service.calculateSRF(1200), equals(2.5));
      // 1700 - 1700 = 0 <= 600
      expect(service.calculateSRF(1700), equals(2.5));
      // 1700 - 2000 = -300 <= 600
      expect(service.calculateSRF(2000), equals(2.5));
    });

    test('SRF 边界值: depth=1100 时 (1700-1100)=600, 不大于600, SRF=2.5', () {
      expect(service.calculateSRF(1100), equals(2.5));
    });
  });

  group('JciCalculatorService - calculateQ', () {
    // Feature: jci-calculation, Q 系统计算
    // **Validates: Requirements 4.9**

    test('Q = (RQD_value / Jn) × 0.33 × (1 / SRF) 已知值验证', () {
      // indicator1=0.3 → Jn=9, indicator3=2.0.
      // RQD_value=0.15, depth=500 → SRF=7.5.
      // Q = (0.15 / 9) × 0.33 × (1 / 7.5)
      final q = service.calculateQ(0.3, 2, 500);
      const expected = (0.15 / 9) * 0.33 * (1 / 7.5);
      expect(q, closeTo(expected, 1e-10));
    });

    test('Q 使用不同参数组合验证', () {
      // indicator1=3.0 → Jn=0.5, indicator3=0.1.
      // RQD_value=1.0, depth=1200 → SRF=2.5.
      // Q = (1.0 / 0.5) × 0.33 × (1 / 2.5)
      final q = service.calculateQ(3, 0.1, 1200);
      const expected = (1.0 / 0.5) * 0.33 * (1 / 2.5);
      expect(q, closeTo(expected, 1e-10));
    });

    test('Q 值始终为正数（RQD_value > 0, Jn > 0, SRF > 0）', () {
      final random = Random(42);
      for (var i = 0; i < 100; i++) {
        final indicator1 = random.nextDouble() * 5;
        final indicator3 = random.nextDouble() * 3;
        final depth = random.nextDouble() * 2000;
        final q = service.calculateQ(indicator1, indicator3, depth);
        expect(q, greaterThan(0), reason: '迭代 $i: Q 值应始终为正数');
      }
    });
  });

  group('JciCalculatorService - Property 6: Q 系统计算公式正确性', () {
    // Feature: jci-calculation, Property 6: Q 系统计算公式正确性
    // **Validates: Requirements 4.5, 4.6, 4.8, 4.9**

    /// 独立的 RQD_value 查表实现（测试预言）
    double expectedRQDValue(double indicator3) {
      if (indicator3 >= 1.571) return 0.15;
      if (indicator3 >= 1.097) return 0.4;
      if (indicator3 >= 0.659) return 0.5;
      if (indicator3 >= 0.276) return 0.85;
      return 1;
    }

    /// 独立的 Jn 查表实现（测试预言）
    double expectedJn(double indicator1) {
      if (indicator1 <= 0.58) return 9;
      if (indicator1 <= 0.91) return 6;
      if (indicator1 <= 1.18) return 4;
      if (indicator1 <= 1.45) return 3;
      if (indicator1 <= 1.92) return 2;
      if (indicator1 <= 2.76) return 1;
      return 0.5;
    }

    /// 独立的 SRF 计算实现（测试预言）
    double expectedSRF(double depth) {
      return (1700 - depth) > 600 ? 7.5 : 2.5;
    }

    test('属性测试: RQD_value 根据 indicator3 查表正确 (100 次迭代)', () {
      final random = Random(54321);

      for (var i = 0; i < 100; i++) {
        final indicator3 = random.nextDouble() * 5; // 0-5

        final actual = service.calculateRQDValue(indicator3);
        final expected = expectedRQDValue(indicator3);

        expect(
          actual,
          equals(expected),
          reason:
              '迭代 $i: indicator3=$indicator3 时 RQD_value 应为 $expected，'
              '但得到 $actual',
        );
      }
    });

    test('属性测试: Jn 根据 indicator1 查表正确 (100 次迭代)', () {
      final random = Random(54321);

      for (var i = 0; i < 100; i++) {
        final indicator1 = random.nextDouble() * 5; // 0-5

        final actual = service.calculateJn(indicator1);
        final expected = expectedJn(indicator1);

        expect(
          actual,
          equals(expected),
          reason:
              '迭代 $i: indicator1=$indicator1 时 Jn 应为 $expected，'
              '但得到 $actual',
        );
      }
    });

    test('属性测试: SRF 根据 (1700-h)>600 判断正确 (100 次迭代)', () {
      final random = Random(54321);

      for (var i = 0; i < 100; i++) {
        final depth = random.nextDouble() * 2000; // 0-2000

        final actual = service.calculateSRF(depth);
        final expected = expectedSRF(depth);

        expect(
          actual,
          equals(expected),
          reason:
              '迭代 $i: depth=$depth 时 SRF 应为 $expected，'
              '但得到 $actual',
        );
      }
    });

    test('属性测试: Q = (RQD_value / Jn) × 0.33 × (1 / SRF) (100 次迭代)', () {
      final random = Random(54321);

      for (var i = 0; i < 100; i++) {
        final indicator1 = random.nextDouble() * 5; // 0-5
        final indicator3 = random.nextDouble() * 5; // 0-5
        final depth = random.nextDouble() * 2000; // 0-2000

        final actualQ = service.calculateQ(indicator1, indicator3, depth);

        final rqdValue = expectedRQDValue(indicator3);
        final jn = expectedJn(indicator1);
        final srf = expectedSRF(depth);
        final expectedQ = (rqdValue / jn) * 0.33 * (1 / srf);

        expect(
          actualQ,
          closeTo(expectedQ, 1e-10),
          reason:
              '迭代 $i: indicator1=$indicator1, indicator3=$indicator3, '
              'depth=$depth 时 Q 应为 $expectedQ '
              '(($rqdValue / $jn) × 0.33 × (1 / $srf))，但得到 $actualQ',
        );
      }
    });
  });

  group('JciCalculatorService - Property 7: 端到端 JCI 公式正确性', () {
    // Feature: jci-calculation, Property 7: 端到端 JCI 公式正确性
    // **Validates: Requirements 4.10, 4.11, 4.12**

    /// 独立的 R2 查表实现（测试预言）
    int oracleR2(double indicator3) {
      if (indicator3 >= 1.571) return 3;
      if (indicator3 >= 1.097) return 8;
      if (indicator3 >= 0.659) return 10;
      if (indicator3 >= 0.276) return 17;
      return 20;
    }

    /// 独立的 R3 查表实现（测试预言）
    int oracleR3(double indicator2) {
      if (indicator2 <= 30) return 3;
      if (indicator2 <= 50) return 8;
      if (indicator2 <= 110) return 10;
      if (indicator2 <= 200) return 17;
      return 20;
    }

    /// 独立的 RQD_value 查表实现（测试预言）
    double oracleRQDValue(double indicator3) {
      if (indicator3 >= 1.571) return 0.15;
      if (indicator3 >= 1.097) return 0.4;
      if (indicator3 >= 0.659) return 0.5;
      if (indicator3 >= 0.276) return 0.85;
      return 1;
    }

    /// 独立的 Jn 查表实现（测试预言）
    double oracleJn(double indicator1) {
      if (indicator1 <= 0.58) return 9;
      if (indicator1 <= 0.91) return 6;
      if (indicator1 <= 1.18) return 4;
      if (indicator1 <= 1.45) return 3;
      if (indicator1 <= 1.92) return 2;
      if (indicator1 <= 2.76) return 1;
      return 0.5;
    }

    /// 独立的 SRF 计算实现（测试预言）
    double oracleSRF(double depth) {
      return (1700 - depth) > 600 ? 7.5 : 2.5;
    }

    test(
      '属性测试: JCI = 0.0454×RMR + 0.6586×g(Q) + 0.2960×h(S) (100 次迭代)',
      () {
        final random = Random(99999);

        for (var i = 0; i < 100; i++) {
          final indicator1 = 0.01 + random.nextDouble() * 4.99;
          final indicator2 = 0.01 + random.nextDouble() * 499.99;
          final indicator3 = 0.01 + random.nextDouble() * 4.99;
          final depth = 1.0 + random.nextDouble() * 1999.0;
          final ucsMpa = 1.0 + random.nextDouble() * 220.0;
          final groundStressMpa = 1.0 + random.nextDouble() * 60.0;

          final params = JciInputParameters(
            indicator1: indicator1,
            indicator2: indicator2,
            indicator3: indicator3,
            depth: depth,
            ucsMpa: ucsMpa,
            groundStressMpa: groundStressMpa,
          );

          final result = service.calculate(params);

          // 独立计算 RMR
          final r2 = oracleR2(indicator3);
          final r3 = oracleR3(indicator2);
          final r1 = service.calculateR1(ucsMpa);
          final rmr = r1 + r2 + r3 + 4.0;

          // 独立计算 Q
          final rqdValue = oracleRQDValue(indicator3);
          final jn = oracleJn(indicator1);
          final srf = oracleSRF(depth);
          final q = (rqdValue / jn) * 0.33 * (1 / srf);

          final gQ = 10 * (log(q) / ln10) + 50;
          final s = ucsMpa / groundStressMpa;
          final hS = 15 * (log(s) / ln10);
          final expectedJci = 0.0454 * rmr + 0.6586 * gQ + 0.2960 * hS;

          expect(
            result.jciValue,
            closeTo(expectedJci, 1e-6),
            reason:
                '迭代 $i: indicator1=$indicator1, indicator2=$indicator2, '
                'indicator3=$indicator3, depth=$depth 时 '
                'JCI 应为 $expectedJci，但得到 ${result.jciValue}',
          );
        }
      },
    );
  });
}
