/// JCI 检测模块 - 报告数据模型
///
/// 包含报告生成所需的所有聚合信息，包括图片信息、像素比例、
/// 测线分析结果、裂缝识别结果、推理时间和检测时间。
///
/// 需求: 11.1-11.9
library;

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:equatable/equatable.dart';

/// 报告数据（聚合所有报告所需信息）
///
/// 将检测结果、测线分析数据和裂缝识别结果汇总为结构化数据，
/// 供 ReportGeneratorService 生成文本报告文件。
///
/// 需求:
/// - 11.1: 生成结构化文本报告文件
/// - 11.2: 报告中包含图片信息（路径、尺寸、像素比例）
/// - 11.3: 报告中包含三大指标汇总
/// - 11.4: 报告中包含各测线节理间距统计表
/// - 11.5: 报告中包含各测线详细交点信息
/// - 11.6: 报告中包含裂缝详细列表
/// - 11.7: 报告中包含推理时间
/// - 11.8: 将报告保存为 .txt 文件到本地存储
/// - 11.9: 使用固定格式模板生成报告
class ReportData extends Equatable {
  /// 创建报告数据实例
  const ReportData({
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.pixelRatio,
    required this.rulerLengthCm,
    required this.scanlineResult,
    required this.crackResult,
    required this.inferenceTimeMs,
    required this.timestamp,
    this.engineeringInfo,
    this.extractedParams,
    this.jciResult,
    this.classification,
    this.supportPlan,
    this.manualReview,
  });

  /// 图片路径
  ///
  /// 需求 11.2: 报告中包含图片路径
  final String imagePath;

  /// 图片宽度（像素）
  ///
  /// 需求 11.2: 报告中包含图片尺寸
  final int imageWidth;

  /// 图片高度（像素）
  ///
  /// 需求 11.2: 报告中包含图片尺寸
  final int imageHeight;

  /// 像素比例（cm/像素）
  ///
  /// 需求 11.2: 报告中包含像素比例
  final double pixelRatio;

  /// 尺子实际长度（cm）
  ///
  /// 用于标定像素比例的参考尺子长度
  final double rulerLengthCm;

  /// 测线分析结果
  ///
  /// 需求 11.3: 报告中包含三大指标汇总
  /// 需求 11.4: 报告中包含各测线节理间距统计表
  /// 需求 11.5: 报告中包含各测线详细交点信息
  final ScanlineAnalysisResult scanlineResult;

  /// 裂缝识别结果
  ///
  /// 需求 11.6: 报告中包含裂缝详细列表
  final CrackIdentificationResult crackResult;

  /// 推理时间（毫秒）
  ///
  /// 需求 11.7: 报告中包含推理时间
  final int inferenceTimeMs;

  /// 检测时间
  final DateTime timestamp;

  /// 工程信息。
  final EngineeringInfo? engineeringInfo;

  /// App 展示的提取参数。
  final ExtractedParameters? extractedParams;

  /// JCI 计算结果。
  final JciCalculationResult? jciResult;

  /// 围岩分类结果。
  final RockClassificationResult? classification;

  /// 支护方案建议。
  final SupportPlan? supportPlan;

  /// 人工复核结果。
  final ManualReview? manualReview;

  @override
  List<Object?> get props => [
    imagePath,
    imageWidth,
    imageHeight,
    pixelRatio,
    rulerLengthCm,
    scanlineResult,
    crackResult,
    inferenceTimeMs,
    timestamp,
    engineeringInfo,
    extractedParams,
    jciResult,
    classification,
    supportPlan,
    manualReview,
  ];

  /// 创建副本并更新指定字段
  ReportData copyWith({
    String? imagePath,
    int? imageWidth,
    int? imageHeight,
    double? pixelRatio,
    double? rulerLengthCm,
    ScanlineAnalysisResult? scanlineResult,
    CrackIdentificationResult? crackResult,
    int? inferenceTimeMs,
    DateTime? timestamp,
    EngineeringInfo? engineeringInfo,
    ExtractedParameters? extractedParams,
    JciCalculationResult? jciResult,
    RockClassificationResult? classification,
    SupportPlan? supportPlan,
    ManualReview? manualReview,
  }) {
    return ReportData(
      imagePath: imagePath ?? this.imagePath,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      rulerLengthCm: rulerLengthCm ?? this.rulerLengthCm,
      scanlineResult: scanlineResult ?? this.scanlineResult,
      crackResult: crackResult ?? this.crackResult,
      inferenceTimeMs: inferenceTimeMs ?? this.inferenceTimeMs,
      timestamp: timestamp ?? this.timestamp,
      engineeringInfo: engineeringInfo ?? this.engineeringInfo,
      extractedParams: extractedParams ?? this.extractedParams,
      jciResult: jciResult ?? this.jciResult,
      classification: classification ?? this.classification,
      supportPlan: supportPlan ?? this.supportPlan,
      manualReview: manualReview ?? this.manualReview,
    );
  }
}
