import 'dart:math';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('金川岩性与 UCS', () {
    test('岩性下拉应只包含软件改动文档要求的六类岩石', () {
      expect(
        RockType.values.map((type) => type.displayName).toList(),
        equals([
          '蛇纹大理岩',
          '中厚层大理岩',
          '超基性岩',
          '混合岩',
          '花岗岩',
          '黑云母片麻岩',
        ]),
      );
    });

    test('岩性应映射到文档表格中的 UCS 值', () {
      expect(RockType.serpentineMarble.ucsMpa, equals(80));
      expect(RockType.mediumThickMarble.ucsMpa, equals(35));
      expect(RockType.ultrabasicRock.ucsMpa, equals(40));
      expect(RockType.mixedRock.ucsMpa, equals(25));
      expect(RockType.granite.ucsMpa, equals(28.6));
      expect(RockType.biotiteGneiss.ucsMpa, equals(30));
    });

    test('App 计算输入与 PC 参考公式使用同一岩性 UCS 时结果完全一致', () {
      const appParams = JciInputParameters(
        indicator1: 0.75,
        indicator2: 80,
        indicator3: 0.8,
        depth: 598,
        ucsMpa: RockType.serpentineMarbleUcs,
        groundStressMpa: 20,
      );

      final appResult = JciCalculatorService().calculate(appParams);
      final pcResult = _PcReferenceCalculator.calculate(appParams);

      expect(appResult.jciValue, equals(pcResult.jciValue));
      expect(appResult.componentScores['UCS'], equals(pcResult.ucsMpa));
      expect(appResult.componentScores['R1'], equals(pcResult.r1.toDouble()));
      expect(appResult.componentScores['RMR'], equals(pcResult.rmr));
      expect(appResult.componentScores['Q'], equals(pcResult.qValue));
      expect(appResult.componentScores['S'], equals(pcResult.sValue));
      expect(appResult.componentScores['gQ'], equals(pcResult.gQ));
      expect(appResult.componentScores['hS'], equals(pcResult.hS));
    });

    test('多岩性多指标样例的 App 与 PC 参考计算差异应为 0', () {
      final cases = <JciInputParameters>[
        for (final rockType in RockType.values)
          JciInputParameters(
            indicator1: 0.58,
            indicator2: 30,
            indicator3: 1.571,
            depth: 598,
            ucsMpa: rockType.ucsMpa,
            groundStressMpa: 20,
          ),
        for (final rockType in RockType.values)
          JciInputParameters(
            indicator1: 1.45,
            indicator2: 110,
            indicator3: 0.659,
            depth: 1300,
            ucsMpa: rockType.ucsMpa,
            groundStressMpa: 12,
          ),
        for (final rockType in RockType.values)
          JciInputParameters(
            indicator1: 2.77,
            indicator2: 201,
            indicator3: 0.275,
            depth: 1426,
            ucsMpa: rockType.ucsMpa,
            groundStressMpa: 8,
          ),
      ];

      final appCalculator = JciCalculatorService();

      for (final params in cases) {
        final appResult = appCalculator.calculate(params);
        final pcResult = _PcReferenceCalculator.calculate(params);

        expect(appResult.jciValue - pcResult.jciValue, equals(0));
        expect(appResult.rmr - pcResult.rmr, equals(0));
        expect(appResult.qValue - pcResult.qValue, equals(0));
        expect(appResult.gQ - pcResult.gQ, equals(0));
        expect(appResult.hS - pcResult.hS, equals(0));
        expect(
          appResult.componentScores['UCS'],
          equals(params.ucsMpa),
        );
      }
    });
  });
}

class _PcReferenceCalculator {
  static _PcReferenceResult calculate(JciInputParameters params) {
    final r1 = _r1(params.ucsMpa);
    final r2 = _r2(params.indicator3);
    final r3 = _r3(params.indicator2);
    final rmr = r1 + r2 + r3 + 4.0;
    final rqdValue = _rqdValue(params.indicator3);
    final jn = _jn(params.indicator1);
    final srf = (1700 - params.depth) > 600 ? 7.5 : 2.5;
    final qValue = (rqdValue / jn) * 0.33 * (1 / srf);
    final gQ = 10 * (log(qValue) / ln10) + 50;
    final groundStressMpa =
        params.groundStressMpa ?? ((1700 - params.depth) * 0.027);
    final sValue = params.ucsMpa / groundStressMpa;
    final hS = 15 * (log(sValue) / ln10);
    final jciValue = 0.0454 * rmr + 0.6586 * gQ + 0.2960 * hS;

    return _PcReferenceResult(
      jciValue: jciValue,
      ucsMpa: params.ucsMpa,
      r1: r1,
      rmr: rmr,
      qValue: qValue,
      sValue: sValue,
      gQ: gQ,
      hS: hS,
    );
  }

  static int _r1(double ucsMpa) {
    if (ucsMpa > 180) return 10;
    if (ucsMpa >= 70) return 7;
    if (ucsMpa >= 35) return 3;
    if (ucsMpa >= 25) return 2;
    if (ucsMpa >= 1) return 1;
    return 0;
  }

  static int _r2(double indicator3) {
    if (indicator3 >= 1.571) return 3;
    if (indicator3 >= 1.097) return 8;
    if (indicator3 >= 0.659) return 10;
    if (indicator3 >= 0.276) return 17;
    return 20;
  }

  static int _r3(double indicator2) {
    if (indicator2 <= 30) return 3;
    if (indicator2 <= 50) return 8;
    if (indicator2 <= 110) return 10;
    if (indicator2 <= 200) return 17;
    return 20;
  }

  static double _rqdValue(double indicator3) {
    if (indicator3 >= 1.571) return 0.15;
    if (indicator3 >= 1.097) return 0.4;
    if (indicator3 >= 0.659) return 0.5;
    if (indicator3 >= 0.276) return 0.85;
    return 1;
  }

  static double _jn(double indicator1) {
    if (indicator1 <= 0.58) return 9;
    if (indicator1 <= 0.91) return 6;
    if (indicator1 <= 1.18) return 4;
    if (indicator1 <= 1.45) return 3;
    if (indicator1 <= 1.92) return 2;
    if (indicator1 <= 2.76) return 1;
    return 0.5;
  }
}

class _PcReferenceResult {
  const _PcReferenceResult({
    required this.jciValue,
    required this.ucsMpa,
    required this.r1,
    required this.rmr,
    required this.qValue,
    required this.sValue,
    required this.gQ,
    required this.hS,
  });

  final double jciValue;
  final double ucsMpa;
  final int r1;
  final double rmr;
  final double qValue;
  final double sValue;
  final double gQ;
  final double hS;
}
