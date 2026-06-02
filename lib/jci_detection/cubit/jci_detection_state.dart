/// JCI 检测状态定义
///
/// 使用 sealed class 实现类型安全的状态管理。
/// 包含初始状态、图像选择状态、分析中状态、成功状态和错误状态。
///
/// 需求: 1.1-1.5, 2.1-2.6
library;

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:equatable/equatable.dart';

/// JCI 检测状态基类
///
/// 使用 sealed class 确保所有状态类型在编译时已知，
/// 支持穷尽式模式匹配。
sealed class JciDetectionState extends Equatable {
  const JciDetectionState();
}

/// 初始状态
///
/// 用户刚进入 JCI 检测页面时的状态。
/// 此时尚未选择任何图像。
///
/// 需求: 1.1 - 显示两个图像采集区域
class JciDetectionInitial extends JciDetectionState {
  const JciDetectionInitial({this.modelLoaded = false});

  /// 裂缝检测模型是否已加载
  final bool modelLoaded;

  @override
  List<Object?> get props => [modelLoaded];
}

/// 图像已选择状态
///
/// 用户已选择识别图像时的状态。
/// 第二图像字段保留为历史数据兼容。
///
/// 需求:
/// - 1.3: 显示图像预览并提供"重新选择"选项
/// - 1.4: 未选择识别图像时显示提示
/// - 1.5: 识别图像已采集完成时启用"开始分析"按钮
///
/// Property 3: 图像数量与按钮状态一致性
/// - 当且仅当识别图像已选择时，"开始分析"按钮应启用
class JciDetectionImagesSelected extends JciDetectionState {
  const JciDetectionImagesSelected({
    this.image1Path,
    this.image2Path,
  });

  /// 掌子面图像1的路径
  final String? image1Path;

  /// 兼容旧记录的第二张掌子面图像路径
  final String? image2Path;

  /// 检查是否已选择识别图像
  ///
  /// 用于判断"开始分析"按钮是否应启用。
  /// Property 3: 当且仅当此值为 true 时，按钮应启用。
  bool get canStartAnalysis => image1Path != null;

  /// 检查图像1是否已选择
  bool get hasImage1 => image1Path != null;

  /// 检查图像2是否已选择
  bool get hasImage2 => image2Path != null;

  /// 已选择的图像数量
  int get selectedImageCount => (hasImage1 ? 1 : 0) + (hasImage2 ? 1 : 0);

  @override
  List<Object?> get props => [image1Path, image2Path];

  /// 创建副本并更新指定字段
  JciDetectionImagesSelected copyWith({
    String? image1Path,
    String? image2Path,
    bool clearImage1 = false,
    bool clearImage2 = false,
  }) {
    return JciDetectionImagesSelected(
      image1Path: clearImage1 ? null : (image1Path ?? this.image1Path),
      image2Path: clearImage2 ? null : (image2Path ?? this.image2Path),
    );
  }
}

/// 分析中状态
///
/// 系统正在执行图像分析和 JCI 计算时的状态。
/// 提供当前步骤和进度信息用于 UI 显示。
///
/// 需求:
/// - 2.1: 对两张图像分别执行裂缝检测
/// - 2.2-2.4: 从检测结果中提取参数
class JciDetectionAnalyzing extends JciDetectionState {
  const JciDetectionAnalyzing({
    required this.currentStep,
    required this.progress,
    this.image1Path,
    this.image2Path,
  });

  /// 当前分析步骤
  ///
  /// 可能的值:
  /// - 'detecting': 正在执行裂缝检测
  /// - 'preparing_offline_detection': 正在准备端侧离线识别
  /// - 'offline_detecting': 正在执行端侧离线识别
  /// - 'online_detecting': 正在等待服务器在线识别
  /// - 'online_fallback': 在线识别失败后切换离线识别
  /// - 'extracting': 正在提取参数
  /// - 'calculating': 正在计算 JCI 值
  /// - 'generating_report': 正在生成检测报告
  final String currentStep;

  /// 分析进度 (0.0 - 1.0)
  final double progress;

  /// 掌子面图像1的路径（用于显示）
  final String? image1Path;

  /// 掌子面图像2的路径（用于显示）
  final String? image2Path;

  /// 获取当前步骤的中文描述
  String get currentStepDescription {
    switch (currentStep) {
      case 'detecting':
        return '正在识别裂隙...';
      case 'preparing_offline_detection':
        return '正在准备离线模型识别...';
      case 'preparing_online_detection':
        return '正在准备服务器在线识别...';
      case 'offline_detecting':
        return '正在进行离线识别...';
      case 'online_detecting':
        return '正在等待服务器在线识别...';
      case 'online_fallback':
        return '在线识别失败，正在切换离线识别...';
      case 'extracting':
        return '正在提取参数...';
      case 'calculating':
        return '正在计算 JCI 值...';
      case 'generating_report':
        return '正在生成检测报告...';
      default:
        return '正在分析...';
    }
  }

  /// 获取进度百分比 (0 - 100)
  int get progressPercent => (progress * 100).round();

  @override
  List<Object?> get props => [currentStep, progress, image1Path, image2Path];

  /// 创建副本并更新指定字段
  JciDetectionAnalyzing copyWith({
    String? currentStep,
    double? progress,
    String? image1Path,
    String? image2Path,
  }) {
    return JciDetectionAnalyzing(
      currentStep: currentStep ?? this.currentStep,
      progress: progress ?? this.progress,
      image1Path: image1Path ?? this.image1Path,
      image2Path: image2Path ?? this.image2Path,
    );
  }
}

/// 图像识别参数已就绪状态
///
/// 掌子面图像已经完成裂缝识别和三大指标提取，用户可以先确认指标，
/// 再录入工程信息并执行 JCI 计算。
class JciDetectionParametersReady extends JciDetectionState {
  const JciDetectionParametersReady({
    required this.image1Path,
    required this.image2Path,
    required this.extractedParams,
    this.scanlineResult,
    this.crackResult,
  });

  /// 掌子面识别图像路径
  final String image1Path;

  /// 兼容旧双图像流程的第二图像路径，单图像流程中与 [image1Path] 相同
  final String image2Path;

  /// 图像识别得到的参数
  final ExtractedParameters extractedParams;

  /// 测线分析结果
  final ScanlineAnalysisResult? scanlineResult;

  /// 裂隙连通域识别结果
  final CrackIdentificationResult? crackResult;

  /// 是否已有真实三大指标
  bool get hasThreeIndicators => scanlineResult != null;

  @override
  List<Object?> get props => [
    image1Path,
    image2Path,
    extractedParams,
    scanlineResult,
    crackResult,
  ];
}

/// 分析成功状态
///
/// 图像分析和 JCI 计算成功完成时的状态。
/// 包含完整的检测结果。
///
/// 需求:
/// - 2.5: 显示提取的参数值供用户确认
/// - 4.3: 显示计算得到的 JCI 数值
/// - 5.8: 以醒目的颜色和图标显示等级结果
class JciDetectionSuccess extends JciDetectionState {
  const JciDetectionSuccess({
    required this.result,
  });

  /// 完整的 JCI 检测结果
  final JciDetectionResult result;

  @override
  List<Object?> get props => [result];
}

/// 分析错误状态
///
/// 图像分析或 JCI 计算过程中发生错误时的状态。
/// 包含错误信息用于显示给用户。
///
/// 需求:
/// - 2.6: 图像质量不足导致参数提取失败时显示错误提示
/// - 4.5: 计算过程中出现异常时显示错误信息
class JciDetectionError extends JciDetectionState {
  const JciDetectionError({
    required this.message,
    this.image1Path,
    this.image2Path,
  });

  /// 错误信息
  final String message;

  /// 掌子面图像1的路径（保留已选图像，便于重试）
  final String? image1Path;

  /// 掌子面图像2的路径（保留已选图像，便于重试）
  final String? image2Path;

  @override
  List<Object?> get props => [message, image1Path, image2Path];

  /// 创建副本并更新指定字段
  JciDetectionError copyWith({
    String? message,
    String? image1Path,
    String? image2Path,
  }) {
    return JciDetectionError(
      message: message ?? this.message,
      image1Path: image1Path ?? this.image1Path,
      image2Path: image2Path ?? this.image2Path,
    );
  }
}
