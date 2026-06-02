/// JCI 检测模块 - 裂缝识别数据模型
///
/// 包含单条裂缝信息和裂缝识别结果的模型类。
/// 用于从裂缝掩膜中识别独立裂缝并记录其度量信息。
///
/// 需求: 12.1-12.6
library;

import 'package:equatable/equatable.dart';

/// 单条裂缝信息
///
/// 描述从裂缝掩膜中识别出的一条独立裂缝，
/// 包含其 ID、长度（实际和像素）以及边界框位置。
///
/// 需求:
/// - 12.1: 通过连通域分析识别出每条独立裂缝
/// - 12.2: 计算每条裂缝的像素长度
/// - 12.3: 根据 Pixel_Ratio 将像素长度转换为实际长度（cm）
/// - 12.4: 记录每条裂缝的位置信息（边界框 x, y, w, h）
class CrackInfo extends Equatable {
  /// 创建裂缝信息实例
  const CrackInfo({
    required this.id,
    required this.lengthCm,
    required this.lengthPixels,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// 裂缝 ID
  final int id;

  /// 实际长度（cm）
  ///
  /// 通过像素长度乘以像素比例（Pixel_Ratio）得到
  final double lengthCm;

  /// 像素长度
  ///
  /// 使用骨架化或轮廓周长方法计算
  final int lengthPixels;

  /// 边界框 X 坐标
  final int x;

  /// 边界框 Y 坐标
  final int y;

  /// 边界框宽度
  final int w;

  /// 边界框高度
  final int h;

  @override
  List<Object?> get props => [id, lengthCm, lengthPixels, x, y, w, h];

  /// 创建副本并更新指定字段
  CrackInfo copyWith({
    int? id,
    double? lengthCm,
    int? lengthPixels,
    int? x,
    int? y,
    int? w,
    int? h,
  }) {
    return CrackInfo(
      id: id ?? this.id,
      lengthCm: lengthCm ?? this.lengthCm,
      lengthPixels: lengthPixels ?? this.lengthPixels,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
    );
  }
}

/// 裂缝识别结果
///
/// 包含从裂缝掩膜中识别出的所有独立裂缝列表，
/// 以及裂缝总长度和平均长度的汇总信息。
/// 裂缝列表按长度从大到小排序。
///
/// 需求:
/// - 12.5: 按裂缝长度从大到小排序输出裂缝列表
/// - 12.6: 计算裂缝总长度和平均长度
class CrackIdentificationResult extends Equatable {
  /// 创建裂缝识别结果实例
  const CrackIdentificationResult({
    required this.cracks,
    required this.totalLengthCm,
    required this.averageLengthCm,
  });

  /// 裂缝列表（按长度降序排列）
  final List<CrackInfo> cracks;

  /// 裂缝总长度（cm）
  ///
  /// 所有裂缝 lengthCm 之和
  final double totalLengthCm;

  /// 裂缝平均长度（cm）
  ///
  /// totalLengthCm 除以裂缝数量，无裂缝时为 0
  final double averageLengthCm;

  @override
  List<Object?> get props => [cracks, totalLengthCm, averageLengthCm];

  /// 创建副本并更新指定字段
  CrackIdentificationResult copyWith({
    List<CrackInfo>? cracks,
    double? totalLengthCm,
    double? averageLengthCm,
  }) {
    return CrackIdentificationResult(
      cracks: cracks ?? this.cracks,
      totalLengthCm: totalLengthCm ?? this.totalLengthCm,
      averageLengthCm: averageLengthCm ?? this.averageLengthCm,
    );
  }
}
