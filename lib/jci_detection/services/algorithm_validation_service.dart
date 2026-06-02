/// JCI 图像算法验证服务
///
/// 用真实二值裂隙 mask 复算连通域、测线和三大指标，用于离线/在线
/// 推理结果一致性验证。
library;

import 'dart:math' as math;

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/crack_identifier_service.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';
import 'package:equatable/equatable.dart';

/// 单张 mask 的算法验证结果
class AlgorithmMaskValidationResult extends Equatable {
  /// 创建验证结果
  const AlgorithmMaskValidationResult({
    required this.crackResult,
    required this.scanlineResult,
    required this.crackRatio,
    required this.imageWidth,
    required this.imageHeight,
    required this.pixelRatio,
  });

  /// 裂缝连通域识别结果
  final CrackIdentificationResult crackResult;

  /// 测线与三大指标分析结果
  final ScanlineAnalysisResult scanlineResult;

  /// 裂缝像素占比（%）
  final double crackRatio;

  /// 图像宽度（像素）
  final int imageWidth;

  /// 图像高度（像素）
  final int imageHeight;

  /// 像素比例（cm/像素）
  final double pixelRatio;

  /// 三大指标快捷访问
  ThreeIndicators get indicators => scanlineResult.indicators;

  @override
  List<Object?> get props => [
    crackResult,
    scanlineResult,
    crackRatio,
    imageWidth,
    imageHeight,
    pixelRatio,
  ];
}

/// 线上/离线算法一致性容差
class AlgorithmValidationTolerance extends Equatable {
  /// 创建容差配置
  const AlgorithmValidationTolerance({
    this.minMaskIou = 0.85,
    this.maxCrackRatioDelta = 1.5,
    this.maxIndicator1RelativeError = 0.1,
    this.maxIndicator2RelativeError = 0.1,
    this.maxIndicator3RelativeError = 0.1,
  });

  /// mask IoU 下限
  final double minMaskIou;

  /// 裂缝占比最大绝对误差（百分点）
  final double maxCrackRatioDelta;

  /// indicator1 最大相对误差
  final double maxIndicator1RelativeError;

  /// indicator2 最大相对误差
  final double maxIndicator2RelativeError;

  /// indicator3 最大相对误差
  final double maxIndicator3RelativeError;

  @override
  List<Object?> get props => [
    minMaskIou,
    maxCrackRatioDelta,
    maxIndicator1RelativeError,
    maxIndicator2RelativeError,
    maxIndicator3RelativeError,
  ];
}

/// 一致性比较结果
class AlgorithmComparisonResult extends Equatable {
  /// 创建比较结果
  const AlgorithmComparisonResult({
    required this.maskIou,
    required this.crackRatioDelta,
    required this.indicator1RelativeError,
    required this.indicator2RelativeError,
    required this.indicator3RelativeError,
    required this.failedReasons,
  });

  /// mask IoU
  final double maskIou;

  /// 裂缝占比绝对误差
  final double crackRatioDelta;

  /// indicator1 相对误差
  final double indicator1RelativeError;

  /// indicator2 相对误差
  final double indicator2RelativeError;

  /// indicator3 相对误差
  final double indicator3RelativeError;

  /// 未通过项
  final List<String> failedReasons;

  /// 是否通过容差验证
  bool get isWithinTolerance => failedReasons.isEmpty;

  @override
  List<Object?> get props => [
    maskIou,
    crackRatioDelta,
    indicator1RelativeError,
    indicator2RelativeError,
    indicator3RelativeError,
    failedReasons,
  ];
}

/// 图像算法验证服务
class AlgorithmValidationService {
  /// 创建服务
  const AlgorithmValidationService({
    CrackIdentifierService? crackIdentifierService,
    ScanlineAnalyzerService? scanlineAnalyzerService,
  }) : _crackIdentifierService =
           crackIdentifierService ?? const _DefaultCrackIdentifierService(),
       _scanlineAnalyzerService =
           scanlineAnalyzerService ?? const _DefaultScanlineAnalyzerService();

  final CrackIdentifierService _crackIdentifierService;
  final ScanlineAnalyzerService _scanlineAnalyzerService;

  /// 从真实二值 mask 计算裂缝连通域、测线结果和三大指标
  AlgorithmMaskValidationResult analyzeMask({
    required List<List<bool>> crackMask,
    required double pixelRatio,
    required int imageWidth,
    required int imageHeight,
  }) {
    final effectivePixelRatio = pixelRatio == 0 ? 1.0 : pixelRatio;
    final crackResult = _crackIdentifierService.identifyCracks(
      crackMask: crackMask,
      pixelRatio: effectivePixelRatio,
    );
    final scanlineResult = _scanlineAnalyzerService.analyze(
      crackMask: crackMask,
      pixelRatio: effectivePixelRatio,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      cracks: crackResult.cracks,
    );

    return AlgorithmMaskValidationResult(
      crackResult: crackResult,
      scanlineResult: scanlineResult,
      crackRatio: _calculateCrackRatio(crackMask),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      pixelRatio: effectivePixelRatio,
    );
  }

  /// 对比线上/离线结果是否在容差范围内
  AlgorithmComparisonResult compare({
    required AlgorithmMaskValidationResult local,
    required AlgorithmMaskValidationResult remote,
    required List<List<bool>> localMask,
    required List<List<bool>> remoteMask,
    AlgorithmValidationTolerance tolerance =
        const AlgorithmValidationTolerance(),
  }) {
    final maskIou = calculateMaskIou(localMask, remoteMask);
    final crackRatioDelta = (local.crackRatio - remote.crackRatio).abs();
    final indicator1RelativeError = _relativeError(
      local.indicators.indicator1,
      remote.indicators.indicator1,
    );
    final indicator2RelativeError = _relativeError(
      local.indicators.indicator2,
      remote.indicators.indicator2,
    );
    final indicator3RelativeError = _relativeError(
      local.indicators.indicator3,
      remote.indicators.indicator3,
    );

    final failedReasons = <String>[];
    if (maskIou < tolerance.minMaskIou) {
      failedReasons.add('mask_iou');
    }
    if (crackRatioDelta > tolerance.maxCrackRatioDelta) {
      failedReasons.add('crack_ratio');
    }
    if (indicator1RelativeError > tolerance.maxIndicator1RelativeError) {
      failedReasons.add('indicator1');
    }
    if (indicator2RelativeError > tolerance.maxIndicator2RelativeError) {
      failedReasons.add('indicator2');
    }
    if (indicator3RelativeError > tolerance.maxIndicator3RelativeError) {
      failedReasons.add('indicator3');
    }

    return AlgorithmComparisonResult(
      maskIou: maskIou,
      crackRatioDelta: crackRatioDelta,
      indicator1RelativeError: indicator1RelativeError,
      indicator2RelativeError: indicator2RelativeError,
      indicator3RelativeError: indicator3RelativeError,
      failedReasons: failedReasons,
    );
  }

  /// 计算两个二值 mask 的 IoU
  double calculateMaskIou(List<List<bool>> a, List<List<bool>> b) {
    final height = math.min(a.length, b.length);
    if (height == 0) return 1;

    var intersection = 0;
    var union = 0;
    for (var y = 0; y < height; y++) {
      final width = math.min(a[y].length, b[y].length);
      for (var x = 0; x < width; x++) {
        final av = a[y][x];
        final bv = b[y][x];
        if (av && bv) {
          intersection++;
        }
        if (av || bv) {
          union++;
        }
      }
    }

    return union == 0 ? 1 : intersection / union;
  }

  double _calculateCrackRatio(List<List<bool>> mask) {
    var crackPixels = 0;
    var totalPixels = 0;
    for (final row in mask) {
      for (final pixel in row) {
        totalPixels++;
        if (pixel) {
          crackPixels++;
        }
      }
    }
    return totalPixels == 0 ? 0 : crackPixels / totalPixels * 100;
  }

  double _relativeError(double expected, double actual) {
    final denominator = expected.abs();
    if (denominator < 1e-9) {
      return actual.abs();
    }
    return (actual - expected).abs() / denominator;
  }
}

class _DefaultCrackIdentifierService extends CrackIdentifierService {
  const _DefaultCrackIdentifierService();
}

class _DefaultScanlineAnalyzerService extends ScanlineAnalyzerService {
  const _DefaultScanlineAnalyzerService();
}
