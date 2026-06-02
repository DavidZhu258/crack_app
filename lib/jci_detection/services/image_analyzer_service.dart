/// 图像分析服务
///
/// 从裂缝检测结果中提取 RQD 值、节理间距、节理面密度等参数。
/// 复用现有的 CrackDetectionService 进行图像分析。
/// 可选集成 CrackIdentifierService 和 ScanlineAnalyzerService
/// 进行裂缝独立识别和测线分析。
///
/// 需求:
/// - 2.1: 对两张图像分别执行裂缝检测
/// - 2.2: 从检测结果中提取 RQD 值
/// - 2.3: 从检测结果中计算节理间距
/// - 2.4: 从检测结果中计算节理面密度
/// - 2.5: 显示提取的参数值供用户确认或手动调整
/// - 2.6: 图像质量不足时显示错误提示
/// - 10.1-10.9: 测线分析与三大指标计算
/// - 12.1-12.6: 裂缝独立识别与度量
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';
import 'package:crack_app/crack_detection/services/inference_router.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/services/crack_identifier_service.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';

/// 图像分析异常
///
/// 当图像质量不足或分析失败时抛出
class ImageAnalysisException implements Exception {
  /// 创建图像分析异常
  const ImageAnalysisException(this.message);

  /// 错误信息
  final String message;

  @override
  String toString() => 'ImageAnalysisException: $message';
}

/// 图像分析服务
///
/// 从裂缝检测结果中提取 JCI 计算所需的参数。
/// 使用简化算法从 crackRatio 推导 RQD、节理间距和节理面密度。
///
/// 当提供 [CrackIdentifierService] 和 [ScanlineAnalyzerService] 时，
/// 还会执行裂缝独立识别和测线分析，返回包含完整数据的
/// [ExtractedParametersV2]。
///
/// Property 8: 参数提取范围有效性
/// - RQD 值在 0-100 范围内
/// - 节理间距为非负数
/// - 节理面密度为非负数
class ImageAnalyzerService {
  /// 创建图像分析服务实例
  ///
  /// [crackService] 裂缝检测服务，用于执行图像分析
  /// [crackIdentifierService] 裂缝独立识别服务（可选）
  /// [scanlineAnalyzerService] 测线分析服务（可选）
  ImageAnalyzerService({
    required CrackDetectionService crackService,
    CrackIdentifierService? crackIdentifierService,
    ScanlineAnalyzerService? scanlineAnalyzerService,
    InferenceRouter? inferenceRouter,
    InferenceMode inferenceMode = InferenceMode.auto,
    int? maxInferenceWindows,
  }) : _crackService = crackService,
       _crackIdentifierService = crackIdentifierService,
       _scanlineAnalyzerService = scanlineAnalyzerService,
       _inferenceRouter = inferenceRouter,
       _inferenceMode = inferenceMode,
       _maxInferenceWindows =
           maxInferenceWindows ?? _defaultMaxInferenceWindows;

  final CrackDetectionService _crackService;
  final CrackIdentifierService? _crackIdentifierService;
  final ScanlineAnalyzerService? _scanlineAnalyzerService;
  final InferenceRouter? _inferenceRouter;
  final InferenceMode _inferenceMode;
  final int _maxInferenceWindows;

  static const int _defaultMaxInferenceWindows = 20;

  /// 裂缝比例阈值，超过此值认为图像质量不足
  static const double _maxCrackRatioThreshold = 80;

  /// RQD 计算因子
  ///
  /// RQD = 100 - (crackRatio * factor)，然后 clamp 到 0-100
  static const double _rqdFactor = 2;

  /// 节理间距基准值（米）
  ///
  /// 当 crackRatio 为 0 时的最大间距
  static const double _baseJointSpacing = 2;

  /// 节理密度因子
  ///
  /// jointDensity = crackRatio * factor
  static const double _jointDensityFactor = 0.5;

  /// 默认像素比例（cm/像素）
  ///
  /// 当未提供像素比例时使用
  static const double _defaultPixelRatio = 1;

  /// Whether this analyzer is configured to prefer server-side inference.
  bool get usesRemoteInference {
    return _inferenceRouter != null &&
        _inferenceMode != InferenceMode.offlineOnly;
  }

  /// 分析两张图像并提取参数
  ///
  /// 对两张掌子面图像分别执行裂缝检测，然后从检测结果中
  /// 提取 RQD 值、节理间距和节理面密度。
  ///
  /// 当提供了 [CrackIdentifierService] 和 [ScanlineAnalyzerService]
  /// 时，还会执行裂缝独立识别和测线分析，返回 [ExtractedParametersV2]。
  ///
  /// [image1Path] 第一张图像的文件路径
  /// [image2Path] 第二张图像的文件路径
  /// [pixelRatio] 像素比例（cm/像素），可选，默认 1.0
  /// [inferenceMode] 本次识别推理模式，可覆盖服务默认值
  /// [maxInferenceWindows] 本次识别覆盖窗口数量，可覆盖服务默认值
  ///
  /// 返回提取的参数。当集成了裂缝识别和测线分析服务时，
  /// 返回 [ExtractedParametersV2]（是 [ExtractedParameters] 的子类型）。
  ///
  /// 抛出 [ImageAnalysisException] 当图像质量不足或分析失败时
  ///
  /// 需求 2.1: 对两张图像分别执行裂缝检测
  /// 需求 2.5: 返回提取的参数供用户确认
  /// 需求 2.6: 图像质量不足时抛出异常
  /// 需求 10.1-10.9: 测线分析与三大指标计算
  /// 需求 12.1-12.6: 裂缝独立识别与度量
  Future<ExtractedParameters> analyzeImages(
    String image1Path,
    String image2Path, {
    double? pixelRatio,
    InferenceMode? inferenceMode,
    int? maxInferenceWindows,
  }) async {
    // 纯本地路径必须先加载手机端模型。远程路径可直接请求服务器，
    // 服务器不可达时再由推理路由决定是否回退本地。
    final effectiveMode = inferenceMode ?? _inferenceMode;
    final usesRouter =
        _inferenceRouter != null && effectiveMode != InferenceMode.offlineOnly;
    if (!usesRouter && !_crackService.isModelLoaded) {
      throw const ImageAnalysisException(
        '裂缝检测模型未加载，请先加载模型',
      );
    }

    // 对两张图像分别执行裂缝检测
    final CrackDetectionResult result1;
    final CrackDetectionResult result2;

    try {
      result1 = await _detectCrack(
        image1Path,
        inferenceMode: effectiveMode,
        maxInferenceWindows: maxInferenceWindows,
      );
    } catch (e) {
      throw ImageAnalysisException('图像1分析失败: $e');
    }

    if (image2Path == image1Path) {
      result2 = result1;
    } else {
      try {
        result2 = await _detectCrack(
          image2Path,
          inferenceMode: effectiveMode,
          maxInferenceWindows: maxInferenceWindows,
        );
      } catch (e) {
        throw ImageAnalysisException('图像2分析失败: $e');
      }
    }

    // 检查图像质量
    _validateImageQuality(result1, '图像1');
    _validateImageQuality(result2, '图像2');

    // 计算两张图像的平均裂缝比例
    final avgCrackRatio = (result1.crackRatio + result2.crackRatio) / 2;

    // 创建合并的检测结果用于参数提取
    final combinedResult = CrackDetectionResult(
      crackRatio: avgCrackRatio,
      inferenceTime: result1.inferenceTime + result2.inferenceTime,
      resultImage: result1.resultImage,
      detectionCount: result1.detectionCount + result2.detectionCount,
      binaryMask: result1.binaryMask,
      originalWidth: result1.originalWidth,
      originalHeight: result1.originalHeight,
      modelVersion: result1.modelVersion,
    );

    // 提取参数
    final rqd = extractRqd(combinedResult);
    final jointSpacing = calculateJointSpacing(combinedResult);
    final jointDensity = calculateJointDensity(combinedResult);

    // 如果裂缝识别和测线分析服务可用，执行扩展分析
    if (_crackIdentifierService != null && _scanlineAnalyzerService != null) {
      return _analyzeWithExtendedServices(
        rqd: rqd,
        jointSpacing: jointSpacing,
        jointDensity: jointDensity,
        resultImage1: result1.resultImage,
        resultImage2: result2.resultImage,
        pixelRatio: pixelRatio ?? _defaultPixelRatio,
        result1: result1,
      );
    }

    return ExtractedParameters(
      rqd: rqd,
      jointSpacing: jointSpacing,
      jointDensity: jointDensity,
      resultImage1: result1.resultImage,
      resultImage2: result2.resultImage,
    );
  }

  Future<CrackDetectionResult> _detectCrack(
    String imagePath, {
    InferenceMode? inferenceMode,
    int? maxInferenceWindows,
  }) {
    final effectiveMode = inferenceMode ?? _inferenceMode;
    final effectiveMaxWindows = maxInferenceWindows ?? _maxInferenceWindows;
    final router = _inferenceRouter;
    if (router != null && effectiveMode != InferenceMode.offlineOnly) {
      return router
          .detect(
            InferenceRequest(
              imagePath: imagePath,
              mode: effectiveMode,
              maxWindows: effectiveMaxWindows,
            ),
          )
          .then((result) => result.detection);
    }

    if (effectiveMaxWindows == _defaultMaxInferenceWindows) {
      return _crackService.detectCrack(imagePath);
    }

    return _crackService.detectCrack(
      imagePath,
      maxWindows: effectiveMaxWindows,
    );
  }

  /// 执行扩展分析（裂缝识别 + 测线分析）
  ///
  /// 使用第一张图像的检测结果进行裂缝识别和测线分析，
  /// 返回包含完整数据的 [ExtractedParametersV2]。
  ///
  /// 需求 10.1-10.9: 测线分析
  /// 需求 12.1-12.6: 裂缝识别
  ExtractedParametersV2 _analyzeWithExtendedServices({
    required double rqd,
    required double jointSpacing,
    required double jointDensity,
    required Uint8List resultImage1,
    required Uint8List resultImage2,
    required double pixelRatio,
    required CrackDetectionResult result1,
  }) {
    final crackMask = result1.binaryMask ?? <List<bool>>[];

    // 需求 12.1-12.6: 裂缝独立识别
    final crackResult = _crackIdentifierService!.identifyCracks(
      crackMask: crackMask,
      pixelRatio: pixelRatio,
    );

    // 需求 10.1-10.9: 测线分析
    final imageWidth = result1.originalWidth > 0
        ? result1.originalWidth
        : (crackMask.isNotEmpty ? crackMask[0].length : 0);
    final imageHeight = result1.originalHeight > 0
        ? result1.originalHeight
        : crackMask.length;

    final scanlineResult = _scanlineAnalyzerService!.analyze(
      crackMask: crackMask,
      pixelRatio: pixelRatio,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      cracks: crackResult.cracks,
    );

    return ExtractedParametersV2(
      rqd: rqd,
      jointSpacing: jointSpacing,
      jointDensity: jointDensity,
      resultImage1: resultImage1,
      resultImage2: resultImage2,
      scanlineResult: scanlineResult,
      crackResult: crackResult,
      pixelRatio: pixelRatio,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  /// 验证图像质量
  ///
  /// 检查裂缝比例是否在合理范围内
  void _validateImageQuality(
    CrackDetectionResult result,
    String imageName,
  ) {
    if (result.crackRatio > _maxCrackRatioThreshold) {
      throw ImageAnalysisException(
        '$imageName质量不足：裂缝比例过高 '
        '(${result.crackRatio.toStringAsFixed(1)}%)，'
        '可能是图像模糊或光线不足，请重新拍摄',
      );
    }
  }

  /// 从裂缝检测结果提取 RQD 值
  ///
  /// RQD (Rock Quality Designation) 表示岩体完整程度。
  /// 使用简化算法：RQD = 100 - (crackRatio * factor)
  /// 结果 clamp 到 0-100 范围。
  ///
  /// [result] 裂缝检测结果
  ///
  /// 返回 RQD 值，范围 0-100
  ///
  /// 需求 2.2: 从检测结果中提取 RQD 值
  /// Property 8: RQD 值在 0-100 范围内
  double extractRqd(CrackDetectionResult result) {
    // 简化算法：裂缝越多，RQD 越低
    // RQD = 100 - (crackRatio * factor)
    final rqd = 100.0 - (result.crackRatio * _rqdFactor);

    // 确保 RQD 在 0-100 范围内
    return rqd.clamp(0.0, 100.0);
  }

  /// 计算节理间距
  ///
  /// 节理间距表示相邻节理面之间的距离。
  /// 使用简化算法：间距与裂缝密度成反比。
  /// 当裂缝比例为 0 时，间距为基准值；
  /// 裂缝比例越高，间距越小。
  ///
  /// [result] 裂缝检测结果
  ///
  /// 返回节理间距（米），非负数
  ///
  /// 需求 2.3: 从检测结果中计算节理间距
  /// Property 8: 节理间距为非负数
  double calculateJointSpacing(CrackDetectionResult result) {
    // 简化算法：间距与裂缝比例成反比
    // spacing = baseSpacing / (1 + crackRatio / 10)
    // 这样当 crackRatio = 0 时，spacing = baseSpacing
    // 当 crackRatio 增加时，spacing 减小但始终为正
    final divisor = 1.0 + (result.crackRatio / 10.0);
    final spacing = _baseJointSpacing / divisor;

    // 确保间距为非负数（理论上已经保证，但为安全起见）
    return math.max(0, spacing);
  }

  /// 计算节理面密度
  ///
  /// 节理面密度表示单位面积内的节理数量。
  /// 使用简化算法：密度与裂缝比例成正比。
  ///
  /// [result] 裂缝检测结果
  ///
  /// 返回节理面密度（条/平方米），非负数
  ///
  /// 需求 2.4: 从检测结果中计算节理面密度
  /// Property 8: 节理面密度为非负数
  double calculateJointDensity(CrackDetectionResult result) {
    // 简化算法：密度与裂缝比例成正比
    // density = crackRatio * factor
    final density = result.crackRatio * _jointDensityFactor;

    // 确保密度为非负数（理论上已经保证，但为安全起见）
    return math.max(0, density);
  }
}
