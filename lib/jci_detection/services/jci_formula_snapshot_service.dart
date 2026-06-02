/// JCI 公式一致性快照服务
library;

import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';

/// 生成跨端可比较的 JCI 公式 canonical JSON。
class JciFormulaSnapshotService {
  /// 创建公式快照服务。
  JciFormulaSnapshotService({JciCalculatorService? calculator})
    : _calculator = calculator ?? JciCalculatorService();

  final JciCalculatorService _calculator;

  /// 生成 canonical 快照。
  Map<String, dynamic> canonicalSnapshot(JciInputParameters params) {
    final result = _calculator.calculate(params);
    final scores = result.componentScores;
    return {
      'input': {
        'indicator1': _f(params.indicator1),
        'indicator2': _f(params.indicator2),
        'indicator3': _f(params.indicator3),
        'elevation': _f(params.depth),
        'ucsMpa': _f(params.ucsMpa),
      },
      'scores': {
        'R1': scores['R1']!.round(),
        'R2': scores['R2']!.round(),
        'R3': scores['R3']!.round(),
        'RMR': _f(scores['RMR']!),
        'RQD_value': _f(scores['RQD_value']!),
        'Jn': _f(scores['Jn']!),
        'SRF': _f(scores['SRF']!),
        'Q': _f(scores['Q']!),
        'gQ': _f(scores['gQ']!),
        'groundStressMpa': _f(scores['groundStressMpa']!),
        'S': _f(scores['S']!),
        'hS': _f(scores['hS']!),
        'JCI': _f(result.jciValue),
      },
    };
  }

  String _f(double value) => value.toStringAsFixed(6);
}
