import 'dart:typed_data';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:equatable/equatable.dart';

/// JCI 分析结果（裂缝检测后处理）
class CrackDetectionJciResult extends Equatable {
  const CrackDetectionJciResult({
    required this.jciValue,
    required this.rockGrade,
    required this.rockGradeDescription,
    required this.supportSummary,
    required this.rmr,
    required this.qValue,
    required this.gQ,
    required this.hS,
    required this.indicator1,
    required this.indicator2,
    required this.indicator3,
    required this.crackCount,
    required this.totalCrackLengthCm,
    this.wasDowngraded = false,
    this.finalGrade,
    this.supportMethods = const [],
  });

  final double jciValue;
  final String rockGrade;
  final String rockGradeDescription;
  final String supportSummary;
  final double rmr;
  final double qValue;
  final double gQ;
  final double hS;
  final double indicator1;
  final double indicator2;
  final double indicator3;
  final int crackCount;
  final double totalCrackLengthCm;
  final bool wasDowngraded;
  final String? finalGrade;
  final List<SupportMethod> supportMethods;

  @override
  List<Object?> get props => [
    jciValue,
    rockGrade,
    rockGradeDescription,
    supportSummary,
    rmr,
    qValue,
    gQ,
    hS,
    indicator1,
    indicator2,
    indicator3,
    crackCount,
    totalCrackLengthCm,
    wasDowngraded,
    finalGrade,
    supportMethods,
  ];
}

/// 裂缝检测状态
sealed class CrackDetectionState extends Equatable {
  const CrackDetectionState();

  @override
  List<Object?> get props => [];
}

/// 初始状态
final class CrackDetectionInitial extends CrackDetectionState {
  const CrackDetectionInitial();
}

/// 模型加载中
final class CrackDetectionModelLoading extends CrackDetectionState {
  const CrackDetectionModelLoading();
}

/// 模型加载成功
final class CrackDetectionModelLoaded extends CrackDetectionState {
  const CrackDetectionModelLoaded();
}

/// 模型加载失败
final class CrackDetectionModelLoadError extends CrackDetectionState {
  const CrackDetectionModelLoadError(this.error);

  final String error;

  @override
  List<Object?> get props => [error];
}

/// 检测中
final class CrackDetectionInProgress extends CrackDetectionState {
  const CrackDetectionInProgress(
    this.imagePath, {
    this.progress = 0,
    this.currentWindow = 0,
    this.totalWindows = 0,
    this.statusText = '正在检测...',
  });

  final String imagePath;
  final double progress;
  final int currentWindow;
  final int totalWindows;
  final String statusText;

  @override
  List<Object?> get props => [
    imagePath,
    progress,
    currentWindow,
    totalWindows,
    statusText,
  ];
}

/// 检测成功
final class CrackDetectionSuccess extends CrackDetectionState {
  const CrackDetectionSuccess({
    required this.originalImagePath,
    required this.resultImage,
    required this.crackRatio,
    required this.inferenceTime,
    required this.detectionCount,
    this.maxWindowsUsed = 20,
    this.binaryMask,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.jciResult,
  });

  final String originalImagePath;
  final Uint8List resultImage;
  final double crackRatio;
  final int inferenceTime;
  final int detectionCount;
  final int maxWindowsUsed;

  /// 二值化裂缝掩膜，用于 JCI 后处理
  final List<List<bool>>? binaryMask;

  /// 原始图像宽度
  final int originalWidth;

  /// 原始图像高度
  final int originalHeight;

  /// JCI 分析结果（点击"JCI 分析"按钮后填充）
  final CrackDetectionJciResult? jciResult;

  @override
  List<Object?> get props => [
    originalImagePath,
    resultImage,
    crackRatio,
    inferenceTime,
    detectionCount,
    maxWindowsUsed,
    originalWidth,
    originalHeight,
    jciResult,
  ];
}

/// 检测失败
final class CrackDetectionError extends CrackDetectionState {
  const CrackDetectionError(this.error);

  final String error;

  @override
  List<Object?> get props => [error];
}
