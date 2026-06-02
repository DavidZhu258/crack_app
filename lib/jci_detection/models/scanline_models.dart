/// JCI 检测模块 - 测线分析数据模型
///
/// 包含测线定义、测线交点、测线分析结果、三大指标和完整分析结果的模型类。
/// 用于测线分析服务（ScanlineAnalyzerService）的输入输出。
///
/// 需求: 10.1-10.9
library;

import 'package:equatable/equatable.dart';

/// 测线定义
///
/// 描述一条测线的基本信息，包括名称、方向、位置和范围。
/// 井字形测线包含 2 条横线和 2 条竖线。
///
/// 需求:
/// - 10.1: 在裂缝掩膜上布置井字形测线（2条横线+2条竖线）
class Scanline extends Equatable {
  /// 创建测线定义实例
  const Scanline({
    required this.name,
    required this.isHorizontal,
    required this.position,
    required this.start,
    required this.end,
  });

  /// 测线名称（如"横线1"、"竖线2"）
  final String name;

  /// 是否为横线
  ///
  /// true 表示横线（沿 X 轴方向），false 表示竖线（沿 Y 轴方向）
  final bool isHorizontal;

  /// 位置坐标
  ///
  /// 横线为 Y 坐标，竖线为 X 坐标
  final int position;

  /// 起始坐标
  ///
  /// 横线为起始 X 坐标，竖线为起始 Y 坐标
  final int start;

  /// 结束坐标
  ///
  /// 横线为结束 X 坐标，竖线为结束 Y 坐标
  final int end;

  @override
  List<Object?> get props => [name, isHorizontal, position, start, end];

  /// 创建副本并更新指定字段
  Scanline copyWith({
    String? name,
    bool? isHorizontal,
    int? position,
    int? start,
    int? end,
  }) {
    return Scanline(
      name: name ?? this.name,
      isHorizontal: isHorizontal ?? this.isHorizontal,
      position: position ?? this.position,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

/// 测线交点信息
///
/// 描述一条测线与裂缝掩膜的一个交点，
/// 包含交点标签、像素坐标和距离起点的实际距离。
///
/// 需求:
/// - 10.2: 计算每条测线与裂缝掩膜的交点位置
/// - 10.5: 根据 Pixel_Ratio 将像素距离转换为实际物理距离（cm）
class ScanlineIntersection extends Equatable {
  /// 创建测线交点信息实例
  const ScanlineIntersection({
    required this.label,
    required this.pixelX,
    required this.pixelY,
    required this.distanceFromStart,
  });

  /// 交点标签（如"交点A"、"交点B"）
  final String label;

  /// 像素 X 坐标
  final int pixelX;

  /// 像素 Y 坐标
  final int pixelY;

  /// 距离起点的实际距离（cm）
  ///
  /// 通过像素距离乘以像素比例（Pixel_Ratio）得到
  final double distanceFromStart;

  @override
  List<Object?> get props => [label, pixelX, pixelY, distanceFromStart];

  /// 创建副本并更新指定字段
  ScanlineIntersection copyWith({
    String? label,
    int? pixelX,
    int? pixelY,
    double? distanceFromStart,
  }) {
    return ScanlineIntersection(
      label: label ?? this.label,
      pixelX: pixelX ?? this.pixelX,
      pixelY: pixelY ?? this.pixelY,
      distanceFromStart: distanceFromStart ?? this.distanceFromStart,
    );
  }
}

/// 单条测线分析结果
///
/// 描述一条测线的分析结果，包含名称、节理间距、有效长度、
/// 交点数、交点详情和有效性标记。
///
/// 需求:
/// - 10.3: 计算每条测线的有效长度（第一个交点到最后一个交点的距离）
/// - 10.4: 计算每条测线的节理间距（有效长度除以交点数）
/// - 10.9: 无交点的测线标记为无效并排除出平均值计算
class ScanlineResult extends Equatable {
  /// 创建单条测线分析结果实例
  const ScanlineResult({
    required this.name,
    required this.jointSpacing,
    required this.effectiveLength,
    required this.intersectionCount,
    required this.intersections,
    required this.isValid,
  });

  /// 测线名称（如"横线1"）
  final String name;

  /// 节理间距（cm）
  ///
  /// 有效长度除以交点数，无交点时为 0
  final double jointSpacing;

  /// 有效长度（cm）
  ///
  /// 第一个交点到最后一个交点的距离
  final double effectiveLength;

  /// 交点数
  final int intersectionCount;

  /// 交点详情列表
  final List<ScanlineIntersection> intersections;

  /// 是否有效（有交点）
  ///
  /// 无交点的测线标记为无效，排除出平均值计算
  final bool isValid;

  @override
  List<Object?> get props => [
    name,
    jointSpacing,
    effectiveLength,
    intersectionCount,
    intersections,
    isValid,
  ];

  /// 创建副本并更新指定字段
  ScanlineResult copyWith({
    String? name,
    double? jointSpacing,
    double? effectiveLength,
    int? intersectionCount,
    List<ScanlineIntersection>? intersections,
    bool? isValid,
  }) {
    return ScanlineResult(
      name: name ?? this.name,
      jointSpacing: jointSpacing ?? this.jointSpacing,
      effectiveLength: effectiveLength ?? this.effectiveLength,
      intersectionCount: intersectionCount ?? this.intersectionCount,
      intersections: intersections ?? this.intersections,
      isValid: isValid ?? this.isValid,
    );
  }
}

/// 三大指标结果
///
/// 包含三大岩石质量指标及其计算所需的中间数据。
///
/// 需求:
/// - 10.6: 指标1 = 长度≥25cm的裂隙条数 / 图像实际面积（m²），单位为条/m²
/// - 10.7: 指标2 = 各测线节理间距的平均值（cm）
/// - 10.8: 指标3 = 裂隙总长度（m）/ 图像实际面积（m²），单位为m/m²
class ThreeIndicators extends Equatable {
  /// 创建三大指标结果实例
  const ThreeIndicators({
    required this.indicator1,
    required this.indicator2,
    required this.indicator3,
    required this.totalCracks,
    required this.cracksAbove25cm,
    required this.totalCrackLength,
    required this.imageAreaM2,
  });

  /// 指标1：裂隙条数/面积（条/m²）
  ///
  /// 长度≥25cm的裂隙条数除以图像实际面积（m²）
  final double indicator1;

  /// 指标2：平均节理间距（cm）
  ///
  /// 各有效测线节理间距的平均值
  final double indicator2;

  /// 指标3：节理密度（m/m²）
  ///
  /// 裂隙总长度（m）除以图像实际面积（m²）
  final double indicator3;

  /// 裂隙总数
  final int totalCracks;

  /// 长度≥25cm的裂隙数
  final int cracksAbove25cm;

  /// 裂隙总长度（cm）
  final double totalCrackLength;

  /// 图像实际面积（m²）
  final double imageAreaM2;

  @override
  List<Object?> get props => [
    indicator1,
    indicator2,
    indicator3,
    totalCracks,
    cracksAbove25cm,
    totalCrackLength,
    imageAreaM2,
  ];

  /// 创建副本并更新指定字段
  ThreeIndicators copyWith({
    double? indicator1,
    double? indicator2,
    double? indicator3,
    int? totalCracks,
    int? cracksAbove25cm,
    double? totalCrackLength,
    double? imageAreaM2,
  }) {
    return ThreeIndicators(
      indicator1: indicator1 ?? this.indicator1,
      indicator2: indicator2 ?? this.indicator2,
      indicator3: indicator3 ?? this.indicator3,
      totalCracks: totalCracks ?? this.totalCracks,
      cracksAbove25cm: cracksAbove25cm ?? this.cracksAbove25cm,
      totalCrackLength: totalCrackLength ?? this.totalCrackLength,
      imageAreaM2: imageAreaM2 ?? this.imageAreaM2,
    );
  }
}

/// 测线分析完整结果
///
/// 包含所有测线的分析结果和三大指标汇总。
///
/// 需求:
/// - 10.1-10.9: 测线分析与三大指标计算
class ScanlineAnalysisResult extends Equatable {
  /// 创建测线分析完整结果实例
  const ScanlineAnalysisResult({
    required this.scanlines,
    required this.indicators,
  });

  /// 各测线分析结果
  final List<ScanlineResult> scanlines;

  /// 三大指标
  final ThreeIndicators indicators;

  @override
  List<Object?> get props => [scanlines, indicators];

  /// 创建副本并更新指定字段
  ScanlineAnalysisResult copyWith({
    List<ScanlineResult>? scanlines,
    ThreeIndicators? indicators,
  }) {
    return ScanlineAnalysisResult(
      scanlines: scanlines ?? this.scanlines,
      indicators: indicators ?? this.indicators,
    );
  }
}
