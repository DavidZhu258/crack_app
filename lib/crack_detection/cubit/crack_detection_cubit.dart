import 'dart:developer' as developer;
import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:crack_app/crack_detection/cubit/crack_detection_state.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/jci_detection/services/crack_identifier_service.dart';
import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';
import 'package:crack_app/jci_detection/services/rock_classifier_service.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/support_advisor_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

void _log(Object? message) {
  developer.log('$message', name: 'CrackDetectionCubit');
}

/// 等待 Flutter 完成一次界面绘制后再进入重型原生推理。
typedef WaitForUiFrameBeforeDetection = Future<void> Function();

int _clampWindowCount(int value) => value.clamp(1, 64);

Future<void> _defaultWaitForUiFrameBeforeDetection() {
  return Future<void>.delayed(const Duration(milliseconds: 80));
}

String _offlineDetectionStatusText(String status) {
  final trimmed = status.trim();
  if (trimmed.isEmpty) {
    return '正在进行端侧离线识别...';
  }
  if (trimmed.contains('离线') || trimmed.contains('端侧')) {
    return trimmed;
  }
  if (trimmed.contains('读取')) {
    return '正在读取图像，准备端侧离线识别...';
  }
  if (trimmed.contains('压缩')) {
    return '正在压缩图像，准备端侧离线识别...';
  }
  if (trimmed.contains('生成') || trimmed.contains('后处理')) {
    return '正在生成离线识别结果：$trimmed';
  }
  return '正在进行端侧离线识别：$trimmed';
}

/// 裂缝检测业务逻辑
///
/// 功能：
/// 1. 初始化模型（完全离线）
/// 2. 拍照检测
/// 3. 相册选择检测
/// 4. 管理检测状态
/// 5. 可调节窗口数量控制检测速度
class CrackDetectionCubit extends Cubit<CrackDetectionState> {
  CrackDetectionCubit({
    CrackDetectionService? service,
    ImagePicker? imagePicker,
    int? initialMaxWindows,
    WaitForUiFrameBeforeDetection? waitForUiFrameBeforeDetection,
  }) : _service = service ?? CrackDetectionService(),
       _imagePicker = imagePicker ?? ImagePicker(),
       _maxWindows = _clampWindowCount(
         initialMaxWindows ?? _defaultMaxWindows,
       ),
       _waitForUiFrameBeforeDetection =
           waitForUiFrameBeforeDetection ??
           _defaultWaitForUiFrameBeforeDetection,
       super(const CrackDetectionInitial());

  static const int _defaultJciMaxWindows = int.fromEnvironment(
    'CRACK_JCI_MAX_WINDOWS',
    defaultValue: 4,
  );
  static const int _defaultMaxWindows = int.fromEnvironment(
    'CRACK_DETECTION_MAX_WINDOWS',
    defaultValue: _defaultJciMaxWindows,
  );

  final CrackDetectionService _service;
  final ImagePicker _imagePicker;
  final WaitForUiFrameBeforeDetection _waitForUiFrameBeforeDetection;

  /// 最大窗口数量（影响检测速度和精度）
  int _maxWindows;

  /// 获取当前窗口数量
  int get maxWindows => _maxWindows;

  /// 设置窗口数量
  void setMaxWindows(int value) {
    _maxWindows = _clampWindowCount(value);
  }

  /// 初始化模型
  ///
  /// [modelPath] 模型路径，默认使用ONNX分割模型
  /// [inputSize] 输入尺寸，默认256
  Future<void> initializeModel({
    String modelPath = 'assets/models/savss_256.onnx',
    int inputSize = 256,
  }) async {
    emit(const CrackDetectionModelLoading());

    try {
      await _service.loadModel(
        modelPath: modelPath,
        inputSize: inputSize,
      );
      emit(const CrackDetectionModelLoaded());
    } on Object catch (e) {
      emit(CrackDetectionModelLoadError(e.toString()));
    }
  }

  /// 拍照检测
  Future<void> detectFromCamera() async {
    try {
      // 打开相机拍照
      final photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (photo == null) {
        // 用户取消拍照
        return;
      }

      // 执行检测
      await _detectImage(photo.path);
    } on Object catch (e) {
      emit(CrackDetectionError('拍照失败: $e'));
    }
  }

  /// 从相册选择检测
  Future<void> detectFromGallery() async {
    try {
      // 从相册选择图片
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (image == null) {
        // 用户取消选择
        return;
      }

      // 执行检测
      await _detectImage(image.path);
    } on Object catch (e) {
      emit(CrackDetectionError('选择图片失败: $e'));
    }
  }

  /// 执行图像检测（核心方法 - 完全离线）
  Future<void> _detectImage(String imagePath) async {
    emit(
      CrackDetectionInProgress(
        imagePath,
        statusText: '正在准备离线识别界面...',
      ),
    );
    await _waitForUiFrameBeforeDetection();
    if (isClosed) return;

    try {
      // 检查模型是否已加载
      if (!_service.isModelLoaded) {
        throw Exception('模型未加载，请先初始化模型');
      }

      // 运行离线推理，使用当前设置的窗口数量，带进度回调
      final result = await _service.detectCrack(
        imagePath,
        maxWindows: _maxWindows,
        onProgress: (current, total, status) {
          // 更新进度状态
          emit(
            CrackDetectionInProgress(
              imagePath,
              progress: total > 0 ? current / total : 0,
              currentWindow: current,
              totalWindows: total,
              statusText: _offlineDetectionStatusText(status),
            ),
          );
        },
      );

      // 发送成功状态
      emit(
        CrackDetectionSuccess(
          originalImagePath: imagePath,
          resultImage: result.resultImage,
          crackRatio: result.crackRatio,
          inferenceTime: result.inferenceTime,
          detectionCount: result.detectionCount,
          maxWindowsUsed: _maxWindows,
          binaryMask: result.binaryMask,
          originalWidth: result.originalWidth,
          originalHeight: result.originalHeight,
        ),
      );
    } on Object catch (e) {
      emit(CrackDetectionError('检测失败: $e'));
    }
  }

  /// 使用测试图片进行检测
  ///
  /// [assetPath] assets中的图片路径，例如 'assets/images/test/1.jpg'
  Future<void> detectWithTestImage(String assetPath) async {
    _log('🧪 开始加载测试图片: $assetPath');
    try {
      // 从assets加载测试图片到临时目录
      final imagePath = await _service.loadTestImageFromAssets(assetPath);
      _log('✅ 测试图片已加载到: $imagePath');

      // 执行检测
      await _detectImage(imagePath);
    } on Object catch (e) {
      _log('❌ 测试图片检测失败: $e');
      emit(CrackDetectionError('加载测试图片失败: $e'));
    }
  }

  /// 重置状态
  void reset() {
    emit(const CrackDetectionModelLoaded());
  }

  /// 保存检测结果图到本地
  /// 返回保存的文件路径
  Future<String?> saveResultImage() async {
    final currentState = state;
    if (currentState is! CrackDetectionSuccess) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final crackDir = Directory('${dir.path}/crack_results');
      if (!crackDir.existsSync()) {
        crackDir.createSync(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${crackDir.path}/crack_result_$timestamp.jpg';
      final file = File(filePath);
      await file.writeAsBytes(currentState.resultImage);

      _log('💾 结果图已保存: $filePath');
      return filePath;
    } on Object catch (e) {
      _log('❌ 保存失败: $e');
      return null;
    }
  }

  /// 执行 JCI 后处理分析
  ///
  /// 在裂缝检测完成后，使用检测得到的二值掩膜进行：
  /// 1. 裂缝独立识别（连通域分析）
  /// 2. 测线分析（井字形测线 + 三大指标）
  /// 3. JCI 计算（RMR + Q 系统公式）
  /// 4. 围岩等级分类
  /// 5. 支护方案建议
  ///
  /// [depth] 工程埋深（米）
  /// [pixelRatio] 像素比例（cm/像素）
  /// [hasSeepage] 是否存在渗水
  Future<void> runJciAnalysis({
    required double depth,
    required double pixelRatio,
    bool hasSeepage = false,
  }) async {
    final currentState = state;
    if (currentState is! CrackDetectionSuccess) return;

    final mask = currentState.binaryMask;
    if (mask == null || mask.isEmpty) {
      emit(const CrackDetectionError('无法进行 JCI 分析：裂缝掩膜数据不可用'));
      return;
    }

    try {
      const crackIdentifier = CrackIdentifierService();
      const scanlineAnalyzer = ScanlineAnalyzerService();
      final jciCalculator = JciCalculatorService();
      final rockClassifier = RockClassifierService();
      const supportAdvisor = SupportAdvisorService();

      // 1. 裂缝独立识别
      final crackResult = crackIdentifier.identifyCracks(
        crackMask: mask,
        pixelRatio: pixelRatio,
      );

      // 调试日志：裂缝识别结果
      _log('🔍 JCI分析 - 裂缝识别结果:');
      _log('  掩膜尺寸: ${mask[0].length}x${mask.length}');
      _log('  像素比例: $pixelRatio cm/像素');
      _log('  裂缝总数: ${crackResult.cracks.length}');
      _log('  裂缝总长度: ${crackResult.totalLengthCm.toStringAsFixed(2)} cm');
      if (crackResult.cracks.isNotEmpty) {
        _log(
          '  最长裂缝: ${crackResult.cracks.first.lengthCm.toStringAsFixed(2)} cm '
          '(${crackResult.cracks.first.lengthPixels} 像素)',
        );
        final above25 = crackResult.cracks
            .where((c) => c.lengthCm >= 25)
            .length;
        _log('  长度≥25cm的裂缝: $above25 条');
      }

      // 2. 测线分析
      final imageWidth = mask.isNotEmpty ? mask[0].length : 0;
      final imageHeight = mask.length;
      final scanlineResult = scanlineAnalyzer.analyze(
        crackMask: mask,
        pixelRatio: pixelRatio,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        cracks: crackResult.cracks,
      );

      // 调试日志：三大指标
      final indicators = scanlineResult.indicators;
      _log('📊 JCI分析 - 三大指标:');
      _log('  指标1 (条/m²): ${indicators.indicator1.toStringAsFixed(4)}');
      _log('  指标2 (cm): ${indicators.indicator2.toStringAsFixed(2)}');
      _log('  指标3 (m/m²): ${indicators.indicator3.toStringAsFixed(4)}');
      _log('  图像面积: ${indicators.imageAreaM2.toStringAsFixed(4)} m²');
      _log('  ≥25cm裂缝数: ${indicators.cracksAbove25cm}');
      final jciParams = JciInputParameters(
        indicator1: indicators.indicator1,
        indicator2: indicators.indicator2,
        indicator3: indicators.indicator3,
        depth: depth,
      );
      final jciResult = jciCalculator.calculate(jciParams);

      // 4. 围岩等级分类
      final originalGrade = rockClassifier.classify(jciResult.jciValue);
      final classification = rockClassifier.applySeepageAdjustment(
        originalGrade,
        hasSeepage: hasSeepage,
      );

      // 5. 支护方案
      final supportPlan = supportAdvisor.getSupportPlan(
        classification.finalGrade,
      );

      // 发送带 JCI 结果的成功状态
      emit(
        CrackDetectionSuccess(
          originalImagePath: currentState.originalImagePath,
          resultImage: currentState.resultImage,
          crackRatio: currentState.crackRatio,
          inferenceTime: currentState.inferenceTime,
          detectionCount: currentState.detectionCount,
          maxWindowsUsed: currentState.maxWindowsUsed,
          binaryMask: currentState.binaryMask,
          originalWidth: currentState.originalWidth,
          originalHeight: currentState.originalHeight,
          jciResult: CrackDetectionJciResult(
            jciValue: jciResult.jciValue,
            rockGrade: classification.finalGrade.name,
            rockGradeDescription: classification.finalGrade.description,
            supportSummary: supportPlan.summary,
            rmr: jciResult.rmr,
            qValue: jciResult.qValue,
            gQ: jciResult.gQ,
            hS: jciResult.hS,
            indicator1: indicators.indicator1,
            indicator2: indicators.indicator2,
            indicator3: indicators.indicator3,
            crackCount: crackResult.cracks.length,
            totalCrackLengthCm: crackResult.totalLengthCm,
            wasDowngraded: classification.wasDowngraded,
            finalGrade: classification.wasDowngraded
                ? '${classification.originalGrade.fullName} → '
                      '${classification.finalGrade.fullName}'
                : null,
            supportMethods: supportPlan.methods,
          ),
        ),
      );
    } on Object catch (e) {
      emit(CrackDetectionError('JCI 分析失败: $e'));
    }
  }

  @override
  Future<void> close() {
    _service.dispose();
    return super.close();
  }
}
