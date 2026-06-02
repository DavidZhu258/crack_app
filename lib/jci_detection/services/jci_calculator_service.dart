/// JCI 检测模块 - JCI 计算服务
///
/// 根据输入参数（三大指标 + 工程埋深）使用 RMR + Q 系统公式计算 JCI 值。
///
/// 需求: 4.1-4.12
library;

import 'dart:math';

import 'package:crack_app/jci_detection/models/models.dart';
import 'package:equatable/equatable.dart';

/// JCI 输入参数
///
/// 包含计算 JCI 值所需的所有输入参数：三大指标和工程埋深。
///
/// 需求: 4.1 - 所有必要参数（Indicator_1、Indicator_2、Indicator_3、工程埋深）
class JciInputParameters extends Equatable {
  /// 创建 JCI 输入参数实例
  const JciInputParameters({
    required this.indicator1,
    required this.indicator2,
    required this.indicator3,
    required this.depth,
    this.ucsMpa = 35,
    this.groundStressMpa,
  });

  /// 指标1：裂隙条数/面积（条/m²）
  ///
  /// 长度≥25cm的裂隙条数除以图像实际面积
  final double indicator1;

  /// 指标2：平均节理间距（cm）
  ///
  /// 各测线节理间距的平均值
  final double indicator2;

  /// 指标3：节理密度（m/m²）
  ///
  /// 裂隙总长度（m）除以图像实际面积（m²）
  final double indicator3;

  /// 工程埋深（米）
  final double depth;

  /// 岩石单轴抗压强度（MPa），用于 R1 与 S 计算
  final double ucsMpa;

  /// 地应力（MPa）。为空时由标高/埋深估算，生产接入后可由工程参数传入。
  final double? groundStressMpa;

  @override
  List<Object?> get props => [
    indicator1,
    indicator2,
    indicator3,
    depth,
    ucsMpa,
    groundStressMpa,
  ];

  /// 创建副本并更新指定字段
  JciInputParameters copyWith({
    double? indicator1,
    double? indicator2,
    double? indicator3,
    double? depth,
    double? ucsMpa,
    double? groundStressMpa,
  }) {
    return JciInputParameters(
      indicator1: indicator1 ?? this.indicator1,
      indicator2: indicator2 ?? this.indicator2,
      indicator3: indicator3 ?? this.indicator3,
      depth: depth ?? this.depth,
      ucsMpa: ucsMpa ?? this.ucsMpa,
      groundStressMpa: groundStressMpa ?? this.groundStressMpa,
    );
  }
}

/// JCI 计算服务
///
/// 使用 RMR + Q 系统公式计算 JCI 值。
/// JCI = W1 × RMR + W2 × g(Q) + W3 × h(S)
///
/// Property 5: RMR 计算公式正确性
/// Property 6: Q 系统计算公式正确性
/// Property 7: 端到端 JCI 公式正确性
class JciCalculatorService {
  /// 权重常量
  static const double w1 = 0.0454; // RMR 权重
  static const double w2 = 0.6586; // g(Q) 权重
  static const double w3 = 0.2960; // h(S) 权重

  /// R1 常量（岩石强度评分）
  static const double r1 = 3;

  /// 默认地应力估算系数（MPa/m），用于缺少实测地应力时的 MVP 兜底
  static const double groundStressCoefficient = 0.027;

  /// R4 + R5 + R6 常量（节理状态+地下水+方位）
  static const double r456 = 4;

  /// Jr/Ja 常量
  static const double jrJaRatio = 0.33;

  /// Jw 常量
  static const double jw = 1;

  /// 根据 UCS（MPa）查表计算 R1
  int calculateR1(double ucsMpa) {
    if (ucsMpa > 180) return 10;
    if (ucsMpa >= 70) return 7;
    if (ucsMpa >= 35) return 3;
    if (ucsMpa >= 25) return 2;
    if (ucsMpa >= 1) return 1;
    return 0;
  }

  /// 根据 indicator3（节理密度 m/m²）查表计算 R2
  ///
  /// 需求: 4.3
  int calculateR2(double indicator3) {
    if (indicator3 >= 1.571) return 3;
    if (indicator3 >= 1.097) return 8;
    if (indicator3 >= 0.659) return 10;
    if (indicator3 >= 0.276) return 17;
    return 20;
  }

  /// 根据 indicator2（平均节理间距 cm）查表计算 R3
  ///
  /// 需求: 4.4
  int calculateR3(double indicator2) {
    if (indicator2 <= 30) return 3;
    if (indicator2 <= 50) return 8;
    if (indicator2 <= 110) return 10;
    if (indicator2 <= 200) return 17;
    return 20;
  }

  /// 计算 RMR = R1 + R2 + R3 + R4 + R5 + R6
  ///
  /// 其中 R1 = 3, R4+R5+R6 = 4
  ///
  /// 需求: 4.2
  double calculateRMR(
    double indicator2,
    double indicator3, {
    double ucsMpa = 35,
  }) {
    final r1Value = calculateR1(ucsMpa);
    final r2 = calculateR2(indicator3);
    final r3 = calculateR3(indicator2);
    return r1Value + r2 + r3 + r456;
  }

  /// 根据 indicator3（节理密度 m/m²）查表计算 RQD_value
  ///
  /// 需求: 4.5
  double calculateRQDValue(double indicator3) {
    if (indicator3 >= 1.571) return 0.15;
    if (indicator3 >= 1.097) return 0.4;
    if (indicator3 >= 0.659) return 0.5;
    if (indicator3 >= 0.276) return 0.85;
    return 1;
  }

  /// 根据 indicator1（裂隙条数/面积 条/m²）查表计算 Jn
  ///
  /// 需求: 4.6
  double calculateJn(double indicator1) {
    if (indicator1 <= 0.58) return 9;
    if (indicator1 <= 0.91) return 6;
    if (indicator1 <= 1.18) return 4;
    if (indicator1 <= 1.45) return 3;
    if (indicator1 <= 1.92) return 2;
    if (indicator1 <= 2.76) return 1;
    return 0.5;
  }

  /// 根据工程埋深计算 SRF
  ///
  /// 当 (1700 - h) > 600 时 SRF = 7.5，否则 SRF = 2.5
  ///
  /// 需求: 4.8
  double calculateSRF(double depth) {
    return (1700 - depth) > 600 ? 7.5 : 2.5;
  }

  /// 计算 Q = (RQD_value / Jn) × (Jr/Ja) × (Jw / SRF)
  ///
  /// 其中 Jr/Ja = 0.33, Jw = 1.0
  ///
  /// 需求: 4.9
  double calculateQ(double indicator1, double indicator3, double depth) {
    final rqdValue = calculateRQDValue(indicator3);
    final jn = calculateJn(indicator1);
    final srf = calculateSRF(depth);
    return (rqdValue / jn) * jrJaRatio * (jw / srf);
  }

  /// 计算 g(Q) = 10 × log10(Q) + 50
  ///
  /// 需求: 4.10
  double calculateGQ(double q) {
    return 10 * (log(q) / ln10) + 50;
  }

  /// 缺少实测地应力时，根据标高/埋深估算地应力（MPa）
  double estimateGroundStressMpa(double depth) {
    final overburden = 1700 - depth;
    final effectiveOverburden = overburden > 0 ? overburden : 1.0;
    return effectiveOverburden * groundStressCoefficient;
  }

  /// 计算 S = UCS / 地应力
  double calculateS({
    required double ucsMpa,
    required double groundStressMpa,
  }) {
    if (ucsMpa <= 0) {
      throw ArgumentError.value(ucsMpa, 'ucsMpa', 'UCS 必须大于 0');
    }
    if (groundStressMpa <= 0) {
      throw ArgumentError.value(
        groundStressMpa,
        'groundStressMpa',
        '地应力必须大于 0',
      );
    }
    return ucsMpa / groundStressMpa;
  }

  /// 计算 h(S) = 15 × log10(S)
  double calculateHSFromS(double s) {
    if (s <= 0) {
      throw ArgumentError.value(s, 's', 'S 必须大于 0');
    }
    return 15 * (log(s) / ln10);
  }

  /// 兼容旧调用：按深度估算地应力后计算 h(S)
  double calculateHS(
    double depth, {
    double ucsMpa = 35,
    double? groundStressMpa,
  }) {
    final stress = groundStressMpa ?? estimateGroundStressMpa(depth);
    return calculateHSFromS(
      calculateS(ucsMpa: ucsMpa, groundStressMpa: stress),
    );
  }

  /// 计算 JCI 值
  ///
  /// [params] JCI 输入参数（三大指标 + 工程埋深）
  ///
  /// 返回包含 JCI 值和各项得分明细的计算结果。
  /// JCI = W1 × RMR + W2 × g(Q) + W3 × h(S)
  ///
  /// 需求: 4.1-4.12
  JciCalculationResult calculate(JciInputParameters params) {
    // 计算 RMR
    final r1Value = calculateR1(params.ucsMpa);
    final r2 = calculateR2(params.indicator3);
    final r3 = calculateR3(params.indicator2);
    final rmr = calculateRMR(
      params.indicator2,
      params.indicator3,
      ucsMpa: params.ucsMpa,
    );

    // 计算 Q 系统
    final rqdValue = calculateRQDValue(params.indicator3);
    final jn = calculateJn(params.indicator1);
    final srf = calculateSRF(params.depth);
    final qValue = calculateQ(
      params.indicator1,
      params.indicator3,
      params.depth,
    );

    // 计算 g(Q) 和 h(S)
    final gQ = calculateGQ(qValue);
    final groundStressMpa =
        params.groundStressMpa ?? estimateGroundStressMpa(params.depth);
    final s = calculateS(
      ucsMpa: params.ucsMpa,
      groundStressMpa: groundStressMpa,
    );
    final hS = calculateHSFromS(s);

    // 计算最终 JCI
    final jciValue = w1 * rmr + w2 * gQ + w3 * hS;

    final componentScores = <String, double>{
      'indicator1': params.indicator1,
      'indicator2': params.indicator2,
      'indicator3': params.indicator3,
      'depth': params.depth,
      'UCS': params.ucsMpa,
      'R1': r1Value.toDouble(),
      'R2': r2.toDouble(),
      'R3': r3.toDouble(),
      'RMR': rmr,
      'RQD_value': rqdValue,
      'Jn': jn,
      'SRF': srf,
      'Q': qValue,
      'groundStressMpa': groundStressMpa,
      'S': s,
      'gQ': gQ,
      'hS': hS,
    };

    return JciCalculationResult(
      jciValue: jciValue,
      rmr: rmr,
      r2: r2,
      r3: r3,
      qValue: qValue,
      gQ: gQ,
      hS: hS,
      rqdValue: rqdValue,
      jn: jn,
      srf: srf,
      componentScores: componentScores,
    );
  }
}
