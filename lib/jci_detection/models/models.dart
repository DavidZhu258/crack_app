/// JCI 检测模块 - 数据模型定义
///
/// 包含工程信息、提取参数、计算结果、分类结果、支护方案和检测结果的模型类。
/// 所有模型类都使用 Equatable 实现不可变性和值相等比较。
///
/// 需求: 3.1-3.6, 4.1, 7.1-7.3, 8.3, 10.1-10.9, 12.1-12.6
library;

import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:equatable/equatable.dart';

/// 工程信息
///
/// 包含检测所需的工程相关信息，如岩石种类、埋深、地下水状况等。
///
/// 需求:
/// - 3.1: 提供岩石种类选择
/// - 3.2: 提供工程埋深输入
/// - 3.3: 提供地下水状况选择
/// - 3.4: 提供检测地点输入
/// - 3.5: 提供拍摄人员输入
/// - 3.6: 提供"是否为均质混合岩"的开关选项
class EngineeringInfo extends Equatable {
  /// 创建工程信息实例
  const EngineeringInfo({
    required this.rockType,
    required this.depth,
    required this.waterCondition,
    this.location = '',
    this.projectName = '',
    this.inspector = '',
    this.isHomogeneous = false,
    this.hasSeepage = false,
  });

  /// 岩石种类
  final RockType rockType;

  /// 工程埋深（米）
  final double depth;

  /// 地下水状况
  final WaterCondition waterCondition;

  /// 检测地点
  final String location;

  /// 工程名称
  final String projectName;

  /// 拍摄人员
  final String inspector;

  /// 是否为均质混合岩
  final bool isHomogeneous;

  /// 是否渗水
  final bool hasSeepage;

  /// 软件改动文档字段：工程地点
  String get projectLocation => location;

  /// 软件改动文档字段：施工人员
  String get workerName => inspector;

  /// 软件改动文档字段：工程所在中段标高
  double get elevation => depth;

  @override
  List<Object?> get props => [
    rockType,
    depth,
    waterCondition,
    location,
    projectName,
    inspector,
    isHomogeneous,
    hasSeepage,
  ];

  /// 创建副本并更新指定字段
  EngineeringInfo copyWith({
    RockType? rockType,
    double? depth,
    WaterCondition? waterCondition,
    String? location,
    String? projectName,
    String? inspector,
    bool? isHomogeneous,
    bool? hasSeepage,
  }) {
    return EngineeringInfo(
      rockType: rockType ?? this.rockType,
      depth: depth ?? this.depth,
      waterCondition: waterCondition ?? this.waterCondition,
      location: location ?? this.location,
      projectName: projectName ?? this.projectName,
      inspector: inspector ?? this.inspector,
      isHomogeneous: isHomogeneous ?? this.isHomogeneous,
      hasSeepage: hasSeepage ?? this.hasSeepage,
    );
  }
}

/// 提取的参数
///
/// 从裂缝检测结果中提取的参数，用于 JCI 计算。
///
/// 需求:
/// - 2.2: 从检测结果中提取 RQD 值
/// - 2.3: 从检测结果中计算节理间距
/// - 2.4: 从检测结果中计算节理面密度
class ExtractedParameters extends Equatable {
  /// 创建提取参数实例
  const ExtractedParameters({
    required this.rqd,
    required this.jointSpacing,
    required this.jointDensity,
    required this.resultImage1,
    required this.resultImage2,
  });

  /// RQD 值 (0-100)
  ///
  /// 岩石质量指标，表示岩体完整程度
  final double rqd;

  /// 节理间距（米）
  ///
  /// 相邻节理面之间的距离
  final double jointSpacing;

  /// 节理面密度（条/平方米）
  ///
  /// 单位面积内的节理数量
  final double jointDensity;

  /// 结果图像1（带标注的检测结果）
  final Uint8List resultImage1;

  /// 结果图像2（带标注的检测结果）
  final Uint8List resultImage2;

  @override
  List<Object?> get props => [
    rqd,
    jointSpacing,
    jointDensity,
    resultImage1,
    resultImage2,
  ];

  /// 创建副本并更新指定字段
  ExtractedParameters copyWith({
    double? rqd,
    double? jointSpacing,
    double? jointDensity,
    Uint8List? resultImage1,
    Uint8List? resultImage2,
  }) {
    return ExtractedParameters(
      rqd: rqd ?? this.rqd,
      jointSpacing: jointSpacing ?? this.jointSpacing,
      jointDensity: jointDensity ?? this.jointDensity,
      resultImage1: resultImage1 ?? this.resultImage1,
      resultImage2: resultImage2 ?? this.resultImage2,
    );
  }
}

/// 扩展的提取参数（包含测线和裂缝数据）
///
/// 继承自 [ExtractedParameters]，新增测线分析结果、裂缝识别结果、
/// 像素比例和图像尺寸等字段。作为 [ExtractedParameters] 的子类型，
/// 可以在所有使用 [ExtractedParameters] 的地方使用，保持向后兼容。
///
/// 需求:
/// - 10.1-10.9: 测线分析与三大指标计算
/// - 12.1-12.6: 裂缝独立识别与度量
class ExtractedParametersV2 extends ExtractedParameters {
  /// 创建扩展提取参数实例
  const ExtractedParametersV2({
    required super.rqd,
    required super.jointSpacing,
    required super.jointDensity,
    required super.resultImage1,
    required super.resultImage2,
    this.scanlineResult,
    this.crackResult,
    this.pixelRatio,
    this.imageWidth,
    this.imageHeight,
  });

  /// 测线分析结果
  ///
  /// 包含各测线的交点、有效长度、节理间距和三大指标。
  /// 当未执行测线分析时为 null。
  final ScanlineAnalysisResult? scanlineResult;

  /// 裂缝识别结果
  ///
  /// 包含独立裂缝列表、总长度和平均长度。
  /// 当未执行裂缝识别时为 null。
  final CrackIdentificationResult? crackResult;

  /// 像素比例（cm/像素）
  ///
  /// 通过尺子/标尺标定得到的每像素对应的实际长度。
  /// 当未提供像素比例时为 null。
  final double? pixelRatio;

  /// 图像宽度（像素）
  final int? imageWidth;

  /// 图像高度（像素）
  final int? imageHeight;

  @override
  List<Object?> get props => [
    ...super.props,
    scanlineResult,
    crackResult,
    pixelRatio,
    imageWidth,
    imageHeight,
  ];

  /// 创建副本并更新指定字段
  ExtractedParametersV2 copyWithV2({
    double? rqd,
    double? jointSpacing,
    double? jointDensity,
    Uint8List? resultImage1,
    Uint8List? resultImage2,
    ScanlineAnalysisResult? scanlineResult,
    CrackIdentificationResult? crackResult,
    double? pixelRatio,
    int? imageWidth,
    int? imageHeight,
  }) {
    return ExtractedParametersV2(
      rqd: rqd ?? this.rqd,
      jointSpacing: jointSpacing ?? this.jointSpacing,
      jointDensity: jointDensity ?? this.jointDensity,
      resultImage1: resultImage1 ?? this.resultImage1,
      resultImage2: resultImage2 ?? this.resultImage2,
      scanlineResult: scanlineResult ?? this.scanlineResult,
      crackResult: crackResult ?? this.crackResult,
      pixelRatio: pixelRatio ?? this.pixelRatio,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
    );
  }
}

/// JCI 计算结果
///
/// 包含 JCI 值、中间计算结果（RMR、Q、g(Q)、h(S)）和各项得分明细。
///
/// 需求:
/// - 4.1: 计算 JCI 值
/// - 4.13: 显示计算得到的 JCI 数值及中间计算结果（RMR、Q、g(Q)、h(S)）
class JciCalculationResult extends Equatable {
  /// 创建 JCI 计算结果实例
  const JciCalculationResult({
    required this.jciValue,
    required this.componentScores,
    this.rmr = 0,
    this.r2 = 0,
    this.r3 = 0,
    this.qValue = 0,
    this.gQ = 0,
    this.hS = 0,
    this.rqdValue = 0,
    this.jn = 0,
    this.srf = 0,
  });

  /// JCI 值
  final double jciValue;

  /// RMR 值
  final double rmr;

  /// R2 评分（根据 indicator3 查表）
  final int r2;

  /// R3 评分（根据 indicator2 查表）
  final int r3;

  /// Q 值
  final double qValue;

  /// g(Q) 值 = 10 × log10(Q) + 50
  final double gQ;

  /// h(S) 值 = 15 × log10(S)
  final double hS;

  /// RQD_value（根据 indicator3 查表）
  final double rqdValue;

  /// Jn 值（根据 indicator1 查表）
  final double jn;

  /// SRF 值（根据工程所在中段标高计算）
  final double srf;

  /// 各项得分明细
  ///
  /// 键为参数名称（如"RQD得分"、"节理间距得分"等），值为对应得分
  final Map<String, double> componentScores;

  @override
  List<Object?> get props => [
    jciValue,
    rmr,
    r2,
    r3,
    qValue,
    gQ,
    hS,
    rqdValue,
    jn,
    srf,
    componentScores,
  ];

  /// 创建副本并更新指定字段
  JciCalculationResult copyWith({
    double? jciValue,
    double? rmr,
    int? r2,
    int? r3,
    double? qValue,
    double? gQ,
    double? hS,
    double? rqdValue,
    double? jn,
    double? srf,
    Map<String, double>? componentScores,
  }) {
    return JciCalculationResult(
      jciValue: jciValue ?? this.jciValue,
      rmr: rmr ?? this.rmr,
      r2: r2 ?? this.r2,
      r3: r3 ?? this.r3,
      qValue: qValue ?? this.qValue,
      gQ: gQ ?? this.gQ,
      hS: hS ?? this.hS,
      rqdValue: rqdValue ?? this.rqdValue,
      jn: jn ?? this.jn,
      srf: srf ?? this.srf,
      componentScores: componentScores ?? this.componentScores,
    );
  }
}

/// 围岩分类结果
///
/// 包含原始等级、最终等级、是否降级及降级原因。
///
/// 需求:
/// - 5.1-5.7: 围岩等级分类
/// - 6.2-6.5: 渗水降级处理
class RockClassificationResult extends Equatable {
  /// 创建围岩分类结果实例
  const RockClassificationResult({
    required this.originalGrade,
    required this.finalGrade,
    this.wasDowngraded = false,
    this.downgradeReason,
  });

  /// 原始围岩等级（未考虑渗水）
  final RockGrade originalGrade;

  /// 最终围岩等级（考虑渗水后）
  final RockGrade finalGrade;

  /// 是否因渗水降级
  final bool wasDowngraded;

  /// 降级原因（如"因渗水降级"）
  final String? downgradeReason;

  @override
  List<Object?> get props => [
    originalGrade,
    finalGrade,
    wasDowngraded,
    downgradeReason,
  ];

  /// 创建副本并更新指定字段
  RockClassificationResult copyWith({
    RockGrade? originalGrade,
    RockGrade? finalGrade,
    bool? wasDowngraded,
    String? downgradeReason,
  }) {
    return RockClassificationResult(
      originalGrade: originalGrade ?? this.originalGrade,
      finalGrade: finalGrade ?? this.finalGrade,
      wasDowngraded: wasDowngraded ?? this.wasDowngraded,
      downgradeReason: downgradeReason ?? this.downgradeReason,
    );
  }
}

/// 支护方法
///
/// 描述单个支护工艺及其参数。
///
/// 需求:
/// - 7.2: 输出支护工艺类型
/// - 7.3: 输出支护参数
class SupportMethod extends Equatable {
  /// 创建支护方法实例
  const SupportMethod({
    required this.name,
    required this.parameters,
  });

  /// 支护方法名称（如"锚杆"、"喷射混凝土"）
  final String name;

  /// 支护参数
  ///
  /// 键为参数名称（如"长度"、"间距"），值为参数值（如"2.5m"、"1.0m"）
  final Map<String, String> parameters;

  @override
  List<Object?> get props => [name, parameters];

  /// 创建副本并更新指定字段
  SupportMethod copyWith({
    String? name,
    Map<String, String>? parameters,
  }) {
    return SupportMethod(
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
    );
  }
}

/// 支护方案
///
/// 包含围岩等级对应的完整支护方案。
///
/// 需求:
/// - 7.1: 显示对应等级的支护参数建议
/// - 7.4: 使用预留的支护方案数据库
/// - 7.5: 无对应数据时显示提示
class SupportPlan extends Equatable {
  /// 创建支护方案实例
  const SupportPlan({
    required this.grade,
    required this.methods,
    required this.summary,
    this.isPlaceholder = false,
  });

  /// 对应的围岩等级
  final RockGrade grade;

  /// 支护方法列表
  final List<SupportMethod> methods;

  /// 方案摘要说明
  final String summary;

  /// 是否为预留方案（无具体数据时为 true）
  final bool isPlaceholder;

  @override
  List<Object?> get props => [grade, methods, summary, isPlaceholder];

  /// 创建副本并更新指定字段
  SupportPlan copyWith({
    RockGrade? grade,
    List<SupportMethod>? methods,
    String? summary,
    bool? isPlaceholder,
  }) {
    return SupportPlan(
      grade: grade ?? this.grade,
      methods: methods ?? this.methods,
      summary: summary ?? this.summary,
      isPlaceholder: isPlaceholder ?? this.isPlaceholder,
    );
  }
}

/// 人工复核结果
///
/// 保存用户是否接受识别/分级结果；当不接受时，记录人工判断等级、
/// 人工选择的支护方案、复核人员、复核说明和时间。
class ManualReview extends Equatable {
  /// 创建人工复核结果
  const ManualReview({
    required this.acceptedRecognitionResult,
    required this.reviewedAt,
    this.manualGrade,
    this.selectedSupportPlan,
    this.reviewerName = '',
    this.note = '',
  });

  /// 接受识别结果的快捷构造
  factory ManualReview.accepted({
    String reviewerName = '',
    String note = '',
    DateTime? reviewedAt,
  }) {
    return ManualReview(
      acceptedRecognitionResult: true,
      reviewerName: reviewerName,
      note: note,
      reviewedAt: reviewedAt ?? DateTime.now(),
    );
  }

  /// 不接受识别结果并录入人工判断的快捷构造
  factory ManualReview.rejected({
    required RockGrade manualGrade,
    required SupportPlan selectedSupportPlan,
    String reviewerName = '',
    String note = '',
    DateTime? reviewedAt,
  }) {
    return ManualReview(
      acceptedRecognitionResult: false,
      manualGrade: manualGrade,
      selectedSupportPlan: selectedSupportPlan,
      reviewerName: reviewerName,
      note: note,
      reviewedAt: reviewedAt ?? DateTime.now(),
    );
  }

  /// 是否接受识别结果
  final bool acceptedRecognitionResult;

  /// 人工判断等级；接受识别结果时为空
  final RockGrade? manualGrade;

  /// 人工选择支护方案；接受识别结果时为空
  final SupportPlan? selectedSupportPlan;

  /// 复核人员
  final String reviewerName;

  /// 复核说明
  final String note;

  /// 复核时间
  final DateTime reviewedAt;

  /// 是否存在人工覆盖
  bool get hasOverride => !acceptedRecognitionResult;

  /// 获取最终采用等级
  RockGrade effectiveGrade(RockGrade calculatedGrade) {
    if (acceptedRecognitionResult) {
      return calculatedGrade;
    }
    return manualGrade ?? calculatedGrade;
  }

  /// 获取最终采用支护方案
  SupportPlan effectiveSupportPlan(SupportPlan calculatedPlan) {
    if (acceptedRecognitionResult) {
      return calculatedPlan;
    }
    return selectedSupportPlan ?? calculatedPlan;
  }

  @override
  List<Object?> get props => [
    acceptedRecognitionResult,
    manualGrade,
    selectedSupportPlan,
    reviewerName,
    note,
    reviewedAt,
  ];

  /// 创建副本并更新指定字段
  ManualReview copyWith({
    bool? acceptedRecognitionResult,
    RockGrade? manualGrade,
    SupportPlan? selectedSupportPlan,
    String? reviewerName,
    String? note,
    DateTime? reviewedAt,
  }) {
    return ManualReview(
      acceptedRecognitionResult:
          acceptedRecognitionResult ?? this.acceptedRecognitionResult,
      manualGrade: manualGrade ?? this.manualGrade,
      selectedSupportPlan: selectedSupportPlan ?? this.selectedSupportPlan,
      reviewerName: reviewerName ?? this.reviewerName,
      note: note ?? this.note,
      reviewedAt: reviewedAt ?? this.reviewedAt,
    );
  }
}

/// JCI 检测完整结果
///
/// 包含一次完整 JCI 检测的所有数据，用于保存和展示。
///
/// 需求:
/// - 8.3: 保存的内容包括原始图像、检测结果图、提取参数、JCI 值、
///        围岩等级、支护方案、检测时间、地点、人员信息
/// - 11.1: 检测分析完成后生成结构化文本报告文件
/// - 10.1-10.9: 测线分析与三大指标计算
/// - 12.1-12.6: 裂缝独立识别与度量
class JciDetectionResult extends Equatable {
  /// 创建 JCI 检测结果实例
  const JciDetectionResult({
    required this.id,
    required this.timestamp,
    required this.image1Path,
    required this.image2Path,
    required this.resultImage1,
    required this.resultImage2,
    required this.extractedParams,
    required this.engineeringInfo,
    required this.jciResult,
    required this.classification,
    required this.supportPlan,
    this.reportPath,
    this.scanlineResult,
    this.crackResult,
    this.syncStatus = SyncStatus.localOnly,
    this.remoteRecordId,
    this.syncError,
    this.operatorUserId,
    this.inferenceMode = 'offline',
    this.modelVersion,
    this.updatedAt,
    this.manualReview,
  });

  /// 唯一标识符
  final String id;

  /// 检测时间戳
  final DateTime timestamp;

  /// 原始图像1路径
  final String image1Path;

  /// 原始图像2路径
  final String image2Path;

  /// 结果图像1（带标注）
  final Uint8List resultImage1;

  /// 结果图像2（带标注）
  final Uint8List resultImage2;

  /// 提取的参数
  final ExtractedParameters extractedParams;

  /// 工程信息
  final EngineeringInfo engineeringInfo;

  /// JCI 计算结果
  final JciCalculationResult jciResult;

  /// 围岩分类结果
  final RockClassificationResult classification;

  /// 支护方案
  final SupportPlan supportPlan;

  /// 报告文件路径
  ///
  /// 检测报告保存后的本地文件路径。
  /// 当报告尚未生成或生成失败时为 null。
  ///
  /// 需求 11.1: 生成结构化文本报告文件
  /// 需求 11.8: 将报告保存为 .txt 文件到本地存储
  final String? reportPath;

  /// 测线分析结果
  ///
  /// 包含各测线的交点、有效长度、节理间距和三大指标。
  /// 当未执行测线分析时为 null。
  ///
  /// 需求 10.1-10.9: 测线分析与三大指标计算
  final ScanlineAnalysisResult? scanlineResult;

  /// 裂缝识别结果
  ///
  /// 包含独立裂缝列表、总长度和平均长度。
  /// 当未执行裂缝识别时为 null。
  ///
  /// 需求 12.1-12.6: 裂缝独立识别与度量
  final CrackIdentificationResult? crackResult;

  /// 同步状态
  final SyncStatus syncStatus;

  /// 云端记录 ID
  final String? remoteRecordId;

  /// 最近一次同步错误
  final String? syncError;

  /// 操作用户 ID
  final String? operatorUserId;

  /// 推理模式/来源
  final String inferenceMode;

  /// 模型版本
  final String? modelVersion;

  /// 最近更新时间
  final DateTime? updatedAt;

  /// 人工复核结果
  final ManualReview? manualReview;

  /// 最终采用等级：优先使用人工复核判断
  RockGrade get effectiveGrade {
    return manualReview?.effectiveGrade(classification.finalGrade) ??
        classification.finalGrade;
  }

  /// 最终采用支护方案：优先使用人工复核选择
  SupportPlan get effectiveSupportPlan {
    return manualReview?.effectiveSupportPlan(supportPlan) ?? supportPlan;
  }

  @override
  List<Object?> get props => [
    id,
    timestamp,
    image1Path,
    image2Path,
    resultImage1,
    resultImage2,
    extractedParams,
    engineeringInfo,
    jciResult,
    classification,
    supportPlan,
    reportPath,
    scanlineResult,
    crackResult,
    syncStatus,
    remoteRecordId,
    syncError,
    operatorUserId,
    inferenceMode,
    modelVersion,
    updatedAt,
    manualReview,
  ];

  /// 创建副本并更新指定字段
  JciDetectionResult copyWith({
    String? id,
    DateTime? timestamp,
    String? image1Path,
    String? image2Path,
    Uint8List? resultImage1,
    Uint8List? resultImage2,
    ExtractedParameters? extractedParams,
    EngineeringInfo? engineeringInfo,
    JciCalculationResult? jciResult,
    RockClassificationResult? classification,
    SupportPlan? supportPlan,
    String? reportPath,
    ScanlineAnalysisResult? scanlineResult,
    CrackIdentificationResult? crackResult,
    SyncStatus? syncStatus,
    String? remoteRecordId,
    String? syncError,
    String? operatorUserId,
    String? inferenceMode,
    String? modelVersion,
    DateTime? updatedAt,
    ManualReview? manualReview,
  }) {
    return JciDetectionResult(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      image1Path: image1Path ?? this.image1Path,
      image2Path: image2Path ?? this.image2Path,
      resultImage1: resultImage1 ?? this.resultImage1,
      resultImage2: resultImage2 ?? this.resultImage2,
      extractedParams: extractedParams ?? this.extractedParams,
      engineeringInfo: engineeringInfo ?? this.engineeringInfo,
      jciResult: jciResult ?? this.jciResult,
      classification: classification ?? this.classification,
      supportPlan: supportPlan ?? this.supportPlan,
      reportPath: reportPath ?? this.reportPath,
      scanlineResult: scanlineResult ?? this.scanlineResult,
      crackResult: crackResult ?? this.crackResult,
      syncStatus: syncStatus ?? this.syncStatus,
      remoteRecordId: remoteRecordId ?? this.remoteRecordId,
      syncError: syncError ?? this.syncError,
      operatorUserId: operatorUserId ?? this.operatorUserId,
      inferenceMode: inferenceMode ?? this.inferenceMode,
      modelVersion: modelVersion ?? this.modelVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      manualReview: manualReview ?? this.manualReview,
    );
  }
}
