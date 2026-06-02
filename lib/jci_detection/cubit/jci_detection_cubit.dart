/// JCI 检测 Cubit
///
/// 协调各服务完成 JCI 检测流程，管理检测状态。
/// 包括图像选择、分析、保存和重置功能。
///
/// 需求:
/// - 1.1-1.5: 先图像识别、后工程信息录入
/// - 2.1-2.6: 图像识别参数提取
/// - 4.1-4.5: JCI 值计算
library;

import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_state.dart';
import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/report_data.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/models/standard_image_option.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/image_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';
import 'package:crack_app/jci_detection/services/report_generator_service.dart';
import 'package:crack_app/jci_detection/services/rock_classifier_service.dart';
import 'package:crack_app/jci_detection/services/support_advisor_service.dart';
import 'package:image_picker/image_picker.dart';

/// ID 生成器函数类型
///
/// 用于生成唯一标识符，支持测试时注入自定义实现。
typedef IdGenerator = String Function();

/// Wait hook used to let Flutter render the progress UI before native
/// inference.
typedef WaitBeforeRecognition = Future<void> Function();

/// 默认 ID 生成器
///
/// 使用时间戳和随机数生成唯一 ID。
String defaultIdGenerator() {
  final random = math.Random();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final randomPart = random.nextInt(999999).toString().padLeft(6, '0');
  return 'jci_${timestamp}_$randomPart';
}

Future<void> _defaultWaitBeforeRecognition() {
  return Future<void>.delayed(const Duration(milliseconds: 250));
}

/// JCI 检测 Cubit
///
/// 协调 ImageAnalyzerService、JciCalculatorService、RockClassifierService、
/// SupportAdvisorService 和 JciStorageService 完成完整的检测流程。
///
/// 状态流转:
/// Initial -> ImagesSelected -> Analyzing -> Success/Error
///
/// Property 3: 图像数量与按钮状态一致性
/// - 当且仅当识别图像已选择时，"开始分析"按钮应启用
class JciDetectionCubit extends Cubit<JciDetectionState> {
  /// 创建 JCI 检测 Cubit 实例
  ///
  /// [imageAnalyzerService] 图像分析服务
  /// [jciCalculatorService] JCI 计算服务
  /// [rockClassifierService] 围岩分类服务
  /// [supportAdvisorService] 支护方案建议服务
  /// [jciStorageService] 本地存储服务
  /// [reportGeneratorService] 报告生成服务（可选）
  /// [imagePicker] 图像选择器（可选，用于测试注入）
  /// [idGenerator] ID 生成器函数（可选，用于测试注入）
  JciDetectionCubit({
    required ImageAnalyzerService imageAnalyzerService,
    required CrackDetectionService crackService,
    JciCalculatorService? jciCalculatorService,
    RockClassifierService? rockClassifierService,
    SupportAdvisorService? supportAdvisorService,
    JciStorageService? jciStorageService,
    ReportGeneratorService? reportGeneratorService,
    ImagePicker? imagePicker,
    IdGenerator? idGenerator,
    WaitBeforeRecognition? waitBeforeRecognition,
  }) : _imageAnalyzerService = imageAnalyzerService,
       _crackService = crackService,
       _jciCalculatorService = jciCalculatorService ?? JciCalculatorService(),
       _rockClassifierService =
           rockClassifierService ?? RockClassifierService(),
       _supportAdvisorService =
           supportAdvisorService ?? const SupportAdvisorService(),
       _jciStorageService = jciStorageService ?? JciStorageService(),
       _reportGeneratorService =
           reportGeneratorService ?? ReportGeneratorService(),
       _imagePicker = imagePicker ?? ImagePicker(),
       _idGenerator = idGenerator ?? defaultIdGenerator,
       _waitBeforeRecognition =
           waitBeforeRecognition ?? _defaultWaitBeforeRecognition,
       super(const JciDetectionInitial());

  final ImageAnalyzerService _imageAnalyzerService;
  final CrackDetectionService _crackService;
  final JciCalculatorService _jciCalculatorService;
  final RockClassifierService _rockClassifierService;
  final SupportAdvisorService _supportAdvisorService;
  final JciStorageService _jciStorageService;
  final ReportGeneratorService _reportGeneratorService;
  final ImagePicker _imagePicker;
  final IdGenerator _idGenerator;
  final WaitBeforeRecognition _waitBeforeRecognition;

  /// 当前检测结果（用于保存）
  JciDetectionResult? _currentResult;

  /// 当前已识别但尚未结合工程信息计算的图像参数
  ExtractedParameters? _currentExtractedParams;
  String? _currentImage1Path;
  String? _currentImage2Path;

  /// 模型是否已加载
  bool get isModelLoaded => _crackService.isModelLoaded;

  /// 加载裂缝检测模型
  Future<void> loadModel() async {
    try {
      await _crackService.loadModel();
      // 模型加载成功后发送状态更新，触发 UI 刷新
      if (state is JciDetectionInitial) {
        emit(const JciDetectionInitial(modelLoaded: true));
      }
    } on Exception catch (e) {
      _emitErrorWithImages('模型加载失败: $e');
    }
  }

  /// 使用第一张标准样图。
  ///
  /// 保留旧方法名作为兼容入口，但不再加载旧默认图。
  Future<void> loadTestImages() {
    return loadStandardImage(jciStandardImageOptions.first);
  }

  /// 使用指定标准样图。
  ///
  /// 从 assets 加载标准掌子面图像并设置为当前识别图像。
  Future<void> loadStandardImage(JciStandardImageOption option) async {
    try {
      final path1 = await _crackService.loadTestImageFromAssets(
        option.assetPath,
      );
      _clearRecognitionCache();
      emit(
        JciDetectionImagesSelected(
          image1Path: path1,
          image2Path: path1,
        ),
      );
    } on Exception catch (e) {
      _emitErrorWithImages('加载标准样图失败: $e');
    }
  }

  /// 选择图像
  ///
  /// [index] 图像索引（当前流程仅使用 1；2 保留为兼容旧双图像入口）
  /// [source] 图像来源（相机或相册）
  ///
  /// 需求:
  /// - 1.2: 提供"拍照"和"从相册选择"两种方式
  /// - 1.3: 显示图像预览并提供"重新选择"选项
  /// - 1.5: 识别图像采集完成时启用"开始分析"按钮
  Future<void> selectImage(int index, ImageSource source) async {
    if (index != 1 && index != 2) {
      return;
    }

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );

      if (image == null) {
        // 用户取消选择
        return;
      }

      // 获取当前图像路径
      final currentState = state;
      String? image1Path;
      String? image2Path;

      if (currentState is JciDetectionImagesSelected) {
        image1Path = currentState.image1Path;
        image2Path = currentState.image2Path;
      } else if (currentState is JciDetectionError) {
        image1Path = currentState.image1Path;
        image2Path = currentState.image2Path;
      }

      // 更新对应的图像路径
      if (index == 1) {
        image1Path = image.path;
      } else {
        image2Path = image.path;
      }

      _clearRecognitionCache();
      emit(
        JciDetectionImagesSelected(
          image1Path: image1Path,
          image2Path: image2Path,
        ),
      );
    } on Exception catch (e) {
      _emitErrorWithImages('选择图像失败: $e');
    }
  }

  /// 先执行图像识别和三大指标提取，不要求工程信息。
  Future<void> recognizeImages({
    int? maxInferenceWindows,
    InferenceMode? inferenceMode,
  }) async {
    final image1Path = _image1PathForState(state);
    final image2Path = _image2PathForState(state);

    if (image1Path == null) {
      emit(
        JciDetectionError(
          message: '请先选择掌子面识别图像',
          image1Path: image1Path,
          image2Path: image2Path,
        ),
      );
      return;
    }

    final analysisImage2Path = image2Path ?? image1Path;

    try {
      final extractedParams = await _runImageRecognition(
        image1Path,
        analysisImage2Path,
        inferenceMode: inferenceMode,
        maxInferenceWindows: maxInferenceWindows,
      );
      _cacheRecognition(
        image1Path: image1Path,
        image2Path: analysisImage2Path,
        extractedParams: extractedParams,
      );
      emit(
        JciDetectionParametersReady(
          image1Path: image1Path,
          image2Path: analysisImage2Path,
          extractedParams: extractedParams,
          scanlineResult: _scanlineResultFrom(extractedParams),
          crackResult: _crackResultFrom(extractedParams),
        ),
      );
    } on ImageAnalysisException catch (e) {
      emit(
        JciDetectionError(
          message: e.message,
          image1Path: image1Path,
          image2Path: analysisImage2Path,
        ),
      );
    } on Exception catch (e) {
      emit(
        JciDetectionError(
          message: '识别失败: $e',
          image1Path: image1Path,
          image2Path: analysisImage2Path,
        ),
      );
    }
  }

  /// 使用已识别参数和工程信息计算 JCI，并自动保存本地记录。
  Future<void> calculateWithEngineeringInfo(EngineeringInfo info) async {
    final currentState = state;
    final ExtractedParameters? extractedParams;
    final String? image1Path;
    final String? image2Path;

    if (currentState is JciDetectionParametersReady) {
      extractedParams = currentState.extractedParams;
      image1Path = currentState.image1Path;
      image2Path = currentState.image2Path;
    } else {
      extractedParams = _currentExtractedParams;
      image1Path = _currentImage1Path;
      image2Path = _currentImage2Path;
    }

    if (extractedParams == null || image1Path == null || image2Path == null) {
      emit(
        JciDetectionError(
          message: '请先完成掌子面图像识别',
          image1Path: image1Path,
          image2Path: image2Path,
        ),
      );
      return;
    }

    try {
      await _calculateAndSave(
        info: info,
        image1Path: image1Path,
        image2Path: image2Path,
        extractedParams: extractedParams,
      );
    } on Exception catch (e) {
      emit(
        JciDetectionError(
          message: '分析失败: $e',
          image1Path: image1Path,
          image2Path: image2Path,
        ),
      );
    }
  }

  /// 兼容旧入口：如果尚未识别，则先识别，再计算。
  Future<void> startAnalysis(
    EngineeringInfo info, {
    int? maxInferenceWindows,
    InferenceMode? inferenceMode,
  }) async {
    if (state is! JciDetectionParametersReady &&
        _currentExtractedParams == null) {
      await recognizeImages(
        inferenceMode: inferenceMode,
        maxInferenceWindows: maxInferenceWindows,
      );
    }
    if (state is JciDetectionParametersReady ||
        _currentExtractedParams != null) {
      await calculateWithEngineeringInfo(info);
    }
  }

  Future<ExtractedParameters> _runImageRecognition(
    String image1Path,
    String image2Path, {
    InferenceMode? inferenceMode,
    int? maxInferenceWindows,
  }) async {
    final usesRemoteInference =
        _imageAnalyzerService.usesRemoteInference &&
        inferenceMode != InferenceMode.offlineOnly;
    emit(
      JciDetectionAnalyzing(
        currentStep: usesRemoteInference
            ? 'preparing_online_detection'
            : 'preparing_offline_detection',
        progress: 0.05,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );
    await _waitBeforeRecognition();
    emit(
      JciDetectionAnalyzing(
        currentStep: usesRemoteInference
            ? 'online_detecting'
            : 'offline_detecting',
        progress: 0.1,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );

    final ExtractedParameters extractedParams;
    if (inferenceMode == null && maxInferenceWindows == null) {
      extractedParams = await _imageAnalyzerService.analyzeImages(
        image1Path,
        image2Path,
        pixelRatio: 1,
      );
    } else if (inferenceMode == null) {
      extractedParams = await _imageAnalyzerService.analyzeImages(
        image1Path,
        image2Path,
        pixelRatio: 1,
        maxInferenceWindows: maxInferenceWindows,
      );
    } else if (maxInferenceWindows == null) {
      extractedParams = await _imageAnalyzerService.analyzeImages(
        image1Path,
        image2Path,
        pixelRatio: 1,
        inferenceMode: inferenceMode,
      );
    } else {
      extractedParams = await _imageAnalyzerService.analyzeImages(
        image1Path,
        image2Path,
        pixelRatio: 1,
        inferenceMode: inferenceMode,
        maxInferenceWindows: maxInferenceWindows,
      );
    }

    emit(
      JciDetectionAnalyzing(
        currentStep: 'extracting',
        progress: 0.4,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );

    return extractedParams;
  }

  Future<void> _calculateAndSave({
    required EngineeringInfo info,
    required String image1Path,
    required String image2Path,
    required ExtractedParameters extractedParams,
  }) async {
    emit(
      JciDetectionAnalyzing(
        currentStep: 'calculating',
        progress: 0.6,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );

    final indicators = _threeIndicatorsFrom(extractedParams);

    final jciInputParams = JciInputParameters(
      indicator1: indicators.indicator1,
      indicator2: indicators.indicator2,
      indicator3: indicators.indicator3,
      depth: info.elevation,
      ucsMpa: info.rockType.ucsMpa,
    );

    final jciResult = _jciCalculatorService.calculate(jciInputParams);

    emit(
      JciDetectionAnalyzing(
        currentStep: 'calculating',
        progress: 0.8,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );

    final originalGrade = _rockClassifierService.classify(jciResult.jciValue);
    final classification = _rockClassifierService.applySeepageAdjustment(
      originalGrade,
      hasSeepage: info.hasSeepage,
    );

    final supportPlan = _supportAdvisorService.getSupportPlan(
      classification.finalGrade,
    );

    final resultId = _idGenerator();
    final scanlineResult = _scanlineResultFrom(extractedParams);
    final crackResult = _crackResultFrom(extractedParams);

    emit(
      JciDetectionAnalyzing(
        currentStep: 'generating_report',
        progress: 0.9,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );

    final resultWithoutReport = JciDetectionResult(
      id: resultId,
      timestamp: DateTime.now(),
      image1Path: image1Path,
      image2Path: image2Path,
      resultImage1: extractedParams.resultImage1,
      resultImage2: extractedParams.resultImage2,
      extractedParams: extractedParams,
      engineeringInfo: info,
      jciResult: jciResult,
      classification: classification,
      supportPlan: supportPlan,
      scanlineResult: scanlineResult,
      crackResult: crackResult,
      syncStatus: SyncStatus.pendingUpload,
      modelVersion: extractedParams is ExtractedParametersV2
          ? 'savss_256'
          : null,
      updatedAt: DateTime.now(),
    );

    final reportPath = await _generateReportForResult(resultWithoutReport);
    final result = reportPath == null
        ? resultWithoutReport
        : resultWithoutReport.copyWith(reportPath: reportPath);

    await _jciStorageService.saveResult(result);

    _currentResult = result;
    emit(JciDetectionSuccess(result: result));
  }

  Future<String?> _generateReportForResult(JciDetectionResult result) async {
    final scanlineResult = result.scanlineResult;
    final crackResult = result.crackResult;
    if (scanlineResult == null || crackResult == null) {
      return result.reportPath;
    }
    try {
      final extractedParams = result.extractedParams;
      final reportData = ReportData(
        imagePath: result.image1Path,
        imageWidth: extractedParams is ExtractedParametersV2
            ? (extractedParams.imageWidth ?? 0)
            : 0,
        imageHeight: extractedParams is ExtractedParametersV2
            ? (extractedParams.imageHeight ?? 0)
            : 0,
        pixelRatio: extractedParams is ExtractedParametersV2
            ? (extractedParams.pixelRatio ?? 1.0)
            : 1.0,
        rulerLengthCm: 30,
        scanlineResult: scanlineResult,
        crackResult: crackResult,
        inferenceTimeMs: 0,
        timestamp: result.timestamp,
        engineeringInfo: result.engineeringInfo,
        extractedParams: result.extractedParams,
        jciResult: result.jciResult,
        classification: result.classification,
        supportPlan: result.supportPlan,
        manualReview: result.manualReview,
      );
      final reportContent = _reportGeneratorService.generateReport(reportData);
      return _reportGeneratorService.saveReport(
        content: reportContent,
        outputDir: _getReportOutputDir(result.image1Path),
        fileName: '${result.id}_report.txt',
      );
    } on Exception {
      return result.reportPath;
    }
  }

  String? _image1PathForState(JciDetectionState currentState) {
    return switch (currentState) {
      JciDetectionImagesSelected() => currentState.image1Path,
      JciDetectionParametersReady() => currentState.image1Path,
      JciDetectionAnalyzing() => currentState.image1Path,
      JciDetectionError() => currentState.image1Path,
      _ => null,
    };
  }

  String? _image2PathForState(JciDetectionState currentState) {
    return switch (currentState) {
      JciDetectionImagesSelected() => currentState.image2Path,
      JciDetectionParametersReady() => currentState.image2Path,
      JciDetectionAnalyzing() => currentState.image2Path,
      JciDetectionError() => currentState.image2Path,
      _ => null,
    };
  }

  void _cacheRecognition({
    required String image1Path,
    required String image2Path,
    required ExtractedParameters extractedParams,
  }) {
    _currentImage1Path = image1Path;
    _currentImage2Path = image2Path;
    _currentExtractedParams = extractedParams;
  }

  void _clearRecognitionCache() {
    _currentResult = null;
    _currentExtractedParams = null;
    _currentImage1Path = null;
    _currentImage2Path = null;
  }

  ThreeIndicators _threeIndicatorsFrom(ExtractedParameters extractedParams) {
    final scanlineResult = _scanlineResultFrom(extractedParams);
    if (scanlineResult != null) {
      return scanlineResult.indicators;
    }

    return const ThreeIndicators(
      indicator1: 0,
      indicator2: 0,
      indicator3: 0,
      totalCracks: 0,
      cracksAbove25cm: 0,
      totalCrackLength: 0,
      imageAreaM2: 0,
    );
  }

  ScanlineAnalysisResult? _scanlineResultFrom(
    ExtractedParameters extractedParams,
  ) {
    return extractedParams is ExtractedParametersV2
        ? extractedParams.scanlineResult
        : null;
  }

  CrackIdentificationResult? _crackResultFrom(
    ExtractedParameters extractedParams,
  ) {
    return extractedParams is ExtractedParametersV2
        ? extractedParams.crackResult
        : null;
  }

  /// 保存检测结果
  ///
  /// 将当前检测结果保存到本地存储。
  ///
  /// 需求:
  /// - 8.1: 检测完成后提供"保存结果"按钮
  /// - 8.2: 用户点击保存时将检测结果保存到本地存储
  Future<void> saveResult() async {
    final currentState = state;

    if (currentState is! JciDetectionSuccess) {
      return;
    }

    final result = _currentResult ?? currentState.result;

    try {
      await _jciStorageService.saveResult(result);
    } on Exception catch (e) {
      // 保存失败时发送错误状态，但保留结果
      emit(
        JciDetectionError(
          message: '保存失败: $e',
          image1Path: result.image1Path,
          image2Path: result.image2Path,
        ),
      );
    }
  }

  /// 提交人工复核结果并保存记录。
  ///
  /// 若用户不接受识别结果，复核对象中会包含人工判断等级和自动匹配的支护方案。
  /// 复核后记录重新标记为待上传，确保云端可同步人工标注。
  Future<void> submitManualReview(ManualReview manualReview) async {
    final currentState = state;
    if (currentState is! JciDetectionSuccess) {
      _emitErrorWithImages('请先完成 JCI 计算再进行人工复核');
      return;
    }

    final result = _currentResult ?? currentState.result;
    final reviewedResultWithoutReport = result.copyWith(
      manualReview: manualReview,
      syncStatus: SyncStatus.pendingUpload,
      syncError: '',
      updatedAt: DateTime.now(),
    );
    final reportPath = await _generateReportForResult(
      reviewedResultWithoutReport,
    );
    final reviewedResult = reportPath == null
        ? reviewedResultWithoutReport
        : reviewedResultWithoutReport.copyWith(reportPath: reportPath);

    try {
      await _jciStorageService.saveResult(reviewedResult);
      _currentResult = reviewedResult;
      emit(JciDetectionSuccess(result: reviewedResult));
    } on Exception catch (e) {
      emit(
        JciDetectionError(
          message: '人工复核保存失败: $e',
          image1Path: result.image1Path,
          image2Path: result.image2Path,
        ),
      );
    }
  }

  /// 重置状态
  ///
  /// 将 Cubit 重置为初始状态，清除所有已选图像和结果。
  void reset() {
    _clearRecognitionCache();
    emit(JciDetectionInitial(modelLoaded: _crackService.isModelLoaded));
  }

  /// 清除指定图像
  ///
  /// [index] 要清除的图像索引（1 或 2）
  ///
  /// 需求 1.3: 提供"重新选择"选项
  void clearImage(int index) {
    if (index != 1 && index != 2) {
      return;
    }

    final currentState = state;
    var image1Path = _image1PathForState(currentState);
    var image2Path = _image2PathForState(currentState);

    if (image1Path == null && image2Path == null) {
      return;
    }

    if (index == 1) {
      image1Path = null;
    } else {
      image2Path = null;
    }

    _clearRecognitionCache();

    // 如果两张图像都被清除，返回初始状态
    if (image1Path == null && image2Path == null) {
      emit(JciDetectionInitial(modelLoaded: _crackService.isModelLoaded));
    } else {
      emit(
        JciDetectionImagesSelected(
          image1Path: image1Path,
          image2Path: image2Path,
        ),
      );
    }
  }

  /// 发送错误状态并保留已选图像
  void _emitErrorWithImages(String message) {
    final currentState = state;
    final image1Path = _image1PathForState(currentState);
    final image2Path = _image2PathForState(currentState);

    emit(
      JciDetectionError(
        message: message,
        image1Path: image1Path,
        image2Path: image2Path,
      ),
    );
  }

  /// 获取报告输出目录
  ///
  /// 使用图像所在目录作为报告输出目录。
  /// 如果无法确定目录，使用当前目录。
  String _getReportOutputDir(String imagePath) {
    final lastSeparator = imagePath.lastIndexOf('/');
    if (lastSeparator > 0) {
      return imagePath.substring(0, lastSeparator);
    }
    return '.';
  }
}
