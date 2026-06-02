import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

void _log(Object? message) {
  developer.log('$message', name: 'CrackDetectionService');
}

Future<void> _defaultInferenceDelay(Duration duration) {
  return Future<void>.delayed(duration);
}

/// Delay function used to yield during long local inference.
typedef InferenceDelay = Future<void> Function(Duration duration);

class _DetectionWorkerRequest {
  const _DetectionWorkerRequest({
    required this.modelBytes,
    required this.inputSize,
    required this.imagePath,
    required this.threshold,
    required this.maxWindows,
    required this.progressPort,
  });

  final Uint8List modelBytes;
  final int inputSize;
  final String imagePath;
  final double threshold;
  final int maxWindows;
  final SendPort progressPort;
}

class _DetectionWorkerProgress {
  const _DetectionWorkerProgress(this.current, this.total, this.status);

  final int current;
  final int total;
  final String status;
}

Future<CrackDetectionResult> _runCrackDetectionWorker(
  _DetectionWorkerRequest request,
) async {
  final service = CrackDetectionService(
    // The worker is already off the UI isolate, so avoid nesting ORT isolates.
    // ignore: avoid_redundant_argument_values
    useAsyncInference: false,
    runLocalDetectionInIsolate: false,
    delay: (_) async {},
  );

  try {
    await service.loadModelFromBytes(
      request.modelBytes,
      inputSize: request.inputSize,
    );
    return await service._detectCrackOnCurrentIsolate(
      request.imagePath,
      threshold: request.threshold,
      maxWindows: request.maxWindows,
      onProgress: (current, total, status) {
        request.progressPort.send(
          _DetectionWorkerProgress(current, total, status),
        );
      },
    );
  } finally {
    service.dispose();
  }
}

Future<CrackDetectionResult> _runCrackDetectionRequestInIsolate(
  _DetectionWorkerRequest request,
) {
  return Isolate.run<CrackDetectionResult>(
    () => _runCrackDetectionWorker(request),
    debugName: 'CrackDetectionWorker',
  );
}

/// Execution policy for device-side ONNX inference.
class InferenceExecutionPolicy {
  /// Creates an inference execution policy.
  const InferenceExecutionPolicy({
    this.windowCooldown = const Duration(milliseconds: 80),
    this.cpuChunkRows = 64,
    this.cpuChunkCooldown = Duration.zero,
  });

  /// Cooldown after each inference window so Flutter can render progress.
  final Duration windowCooldown;

  /// Number of processed image rows between UI yields during CPU-heavy loops.
  final int cpuChunkRows;

  /// Cooldown for non-ONNX CPU work chunks.
  final Duration cpuChunkCooldown;

  /// Whether the current number of processed rows should yield to the UI.
  bool shouldYieldAfterCpuRows(int processedRows) {
    return cpuChunkRows > 0 &&
        processedRows > 0 &&
        processedRows % cpuChunkRows == 0;
  }
}

/// 裂缝检测服务 - 使用ONNX Runtime完全离线运行
///
/// 功能：
/// 1. 加载本地ONNX模型（.onnx格式）
/// 2. 图像预处理（resize, normalize）
/// 3. 滑动窗口推理（完全在设备本地运行）
/// 4. 后处理（生成可视化结果）
///
/// 特点：
/// ✅ 完全离线 - 无需网络连接
/// ✅ 本地推理 - 所有计算在设备上完成
/// ✅ 隐私保护 - 图片不上传到服务器
/// ✅ 语义分割 - 像素级裂缝检测
class CrackDetectionService {
  CrackDetectionService({
    bool useAsyncInference = const bool.fromEnvironment(
      'CRACK_USE_ASYNC_ONNX',
    ),
    bool runLocalDetectionInIsolate = const bool.fromEnvironment(
      'CRACK_RUN_LOCAL_DETECTION_IN_ISOLATE',
      defaultValue: true,
    ),
    InferenceExecutionPolicy executionPolicy = const InferenceExecutionPolicy(),
    InferenceDelay? delay,
  }) : _useAsyncInference = useAsyncInference,
       _runLocalDetectionInIsolate = runLocalDetectionInIsolate,
       _executionPolicy = executionPolicy,
       _delay = delay ?? _defaultInferenceDelay;

  OrtSession? _session;
  OrtSessionOptions? _sessionOptions;
  Uint8List? _modelBytes;
  bool _isModelLoaded = false;
  int _inputSize = 256;
  final bool _useAsyncInference;
  final bool _runLocalDetectionInIsolate;
  final InferenceExecutionPolicy _executionPolicy;
  final InferenceDelay _delay;

  // ImageNet标准化参数
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std = [0.229, 0.224, 0.225];

  /// 模型是否已加载
  bool get isModelLoaded => _isModelLoaded;

  /// Exposes the production background-isolate mode for unit tests.
  @visibleForTesting
  bool get runsLocalDetectionInIsolateForTest => _runLocalDetectionInIsolate;

  /// Exposes the production window-yield behavior for unit tests.
  @visibleForTesting
  Future<void> yieldAfterInferenceWindowForTest({
    required int current,
    required int total,
  }) {
    return _yieldAfterInferenceWindow(current: current, total: total);
  }

  /// Exposes the production CPU chunk-yield behavior for unit tests.
  @visibleForTesting
  Future<void> yieldDuringCpuWorkForTest({required int processedRows}) {
    return _yieldDuringCpuWork(processedRows: processedRows);
  }

  /// 加载模型（从assets）
  ///
  /// [modelPath] 模型文件路径，例如 'assets/models/savss_256.onnx'
  /// [inputSize] 输入图像尺寸，默认256
  Future<void> loadModel({
    String modelPath = 'assets/models/savss_256.onnx',
    int inputSize = 256,
  }) async {
    try {
      _log('📥 正在加载ONNX模型: $modelPath');
      _log('📦 输入尺寸: ${inputSize}x$inputSize');

      // 从assets加载模型
      final rawAssetFile = await rootBundle.load(modelPath);
      final bytes = rawAssetFile.buffer.asUint8List(
        rawAssetFile.offsetInBytes,
        rawAssetFile.lengthInBytes,
      );
      await loadModelFromBytes(bytes, inputSize: inputSize);

      _log('✅ ONNX模型加载成功: $modelPath');
    } catch (e) {
      _isModelLoaded = false;
      _log('❌ 模型加载失败: $e');
      rethrow;
    }
  }

  /// Loads an ONNX model from bytes.
  ///
  /// This is used by the background-isolate path because spawned isolates
  /// cannot read Flutter assets through [rootBundle].
  Future<void> loadModelFromBytes(
    Uint8List bytes, {
    int inputSize = 256,
  }) async {
    _releaseSession();
    _modelBytes = Uint8List.fromList(bytes);
    _inputSize = inputSize;

    if (_runLocalDetectionInIsolate) {
      _isModelLoaded = true;
      _log('✅ ONNX模型已缓存，将在后台isolate中运行');
      return;
    }

    _openSession(_modelBytes!);
    _isModelLoaded = true;
  }

  void _openSession(Uint8List bytes) {
    // 初始化ONNX Runtime环境
    OrtEnv.instance.init();

    // 创建会话
    _sessionOptions = OrtSessionOptions();
    _sessionOptions!
      ..setIntraOpNumThreads(1)
      ..setInterOpNumThreads(1)
      ..setSessionGraphOptimizationLevel(
        GraphOptimizationLevel.ortEnableBasic,
      );
    _session = OrtSession.fromBuffer(bytes, _sessionOptions!);
  }

  /// 从assets加载测试图片并保存到临时目录
  ///
  /// [assetPath] assets中的图片路径，例如 'assets/images/test/1.jpg'
  Future<String> loadTestImageFromAssets(String assetPath) async {
    try {
      final byteData = await rootBundle.load(assetPath);
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final tempFile = File('${tempDir.path}/$fileName');

      await tempFile.writeAsBytes(
        byteData.buffer.asUint8List(),
        flush: true,
      );

      return tempFile.path;
    } catch (e) {
      _log('❌ 加载测试图片失败: $e');
      rethrow;
    }
  }

  /// 检测裂缝（完全离线 - 使用ONNX语义分割）
  ///
  /// [imagePath] 图片文件路径
  /// [threshold] 二值化阈值，默认0.3
  /// [maxWindows] 最大滑动窗口数量，默认20
  /// [onProgress] 进度回调
  Future<CrackDetectionResult> detectCrack(
    String imagePath, {
    double threshold = 0.3,
    int maxWindows = 20,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    if (!_isModelLoaded || (!_runLocalDetectionInIsolate && _session == null)) {
      throw Exception('模型未加载，请先调用 loadModel()');
    }

    if (_runLocalDetectionInIsolate) {
      return _detectCrackInBackground(
        imagePath,
        threshold: threshold,
        maxWindows: maxWindows,
        onProgress: onProgress,
      );
    }

    return _detectCrackOnCurrentIsolate(
      imagePath,
      threshold: threshold,
      maxWindows: maxWindows,
      onProgress: onProgress,
    );
  }

  Future<CrackDetectionResult> _detectCrackInBackground(
    String imagePath, {
    required double threshold,
    required int maxWindows,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    final modelBytes = _modelBytes;
    if (modelBytes == null) {
      throw Exception('模型未加载，请先调用 loadModel()');
    }

    onProgress?.call(0, 0, '正在启动后台AI识别...');
    final progressPort = ReceivePort();
    final progressSubscription = progressPort.listen((message) {
      if (message is _DetectionWorkerProgress) {
        onProgress?.call(message.current, message.total, message.status);
      }
    });
    final request = _DetectionWorkerRequest(
      modelBytes: modelBytes,
      inputSize: _inputSize,
      imagePath: imagePath,
      threshold: threshold,
      maxWindows: maxWindows,
      progressPort: progressPort.sendPort,
    );

    try {
      return await _runCrackDetectionRequestInIsolate(request);
    } finally {
      await progressSubscription.cancel();
      progressPort.close();
    }
  }

  Future<CrackDetectionResult> _detectCrackOnCurrentIsolate(
    String imagePath, {
    required double threshold,
    required int maxWindows,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    if (_session == null) {
      throw Exception('模型未加载，请先调用 loadModel()');
    }

    final startTime = DateTime.now();

    try {
      onProgress?.call(0, 0, '正在读取图像...');

      // 1. 读取图像
      final imageFile = File(imagePath);
      final imageBytes = await imageFile.readAsBytes();
      var image = img.decodeImage(imageBytes);

      if (image == null) {
        throw Exception('无法解码图像');
      }

      _log('📸 原始图像尺寸: ${image.width}x${image.height}');

      // 限制图像大小，避免内存溢出（模拟器友好）
      const maxDimension = 800;
      if (image.width > maxDimension || image.height > maxDimension) {
        final scale =
            maxDimension /
            (image.width > image.height ? image.width : image.height);
        final newW = (image.width * scale).toInt();
        final newH = (image.height * scale).toInt();
        onProgress?.call(0, 0, '正在压缩图像...');
        image = img.copyResize(image, width: newW, height: newH);
        _log('📸 压缩后尺寸: ${image.width}x${image.height}');
      }

      // 2. 滑动窗口推理
      _log('🔄 开始ONNX推理...');
      onProgress?.call(0, 0, '正在进行AI推理...');

      final prediction = await _slidingWindowPredict(
        image,
        maxWindows: maxWindows,
        onProgress: onProgress,
      );

      onProgress?.call(0, 0, '正在生成结果...');

      // 3. 后处理 - 二值化
      final binaryMask = await _binarize(prediction, threshold);

      // 4. 计算裂缝占比
      final crackRatio = await _calculateCrackRatioFromMask(binaryMask);

      // 5. 生成结果图像（叠加mask）
      final resultImage = await _drawSegmentationResult(image, binaryMask);

      final inferenceTime = DateTime.now().difference(startTime).inMilliseconds;

      _log(
        '✅ 检测完成 - 裂缝占比: ${crackRatio.toStringAsFixed(2)}%, '
        '耗时: ${inferenceTime}ms',
      );

      return CrackDetectionResult(
        crackRatio: crackRatio,
        inferenceTime: inferenceTime,
        resultImage: resultImage,
        detectionCount: 1, // 语义分割返回1个mask
        binaryMask: binaryMask,
        originalWidth: image.width,
        originalHeight: image.height,
        modelVersion: 'savss_256',
      );
    } catch (e, stackTrace) {
      _log('\n========== 检测失败 ==========');
      _log('❌ 错误类型: ${e.runtimeType}');
      _log('❌ 错误信息: $e');
      _log('❌ 完整堆栈:');
      _log(stackTrace);
      _log('================================\n');
      rethrow;
    }
  }

  /// 滑动窗口预测
  Future<List<List<double>>> _slidingWindowPredict(
    img.Image image, {
    int maxWindows = 20,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    final origH = image.height;
    final origW = image.width;

    // 计算缩放比例
    const overlap = 0.25;
    final stride = (_inputSize * (1 - overlap)).toInt();
    final windowsPerSide = math.sqrt(maxWindows).toInt();
    final targetSide = (windowsPerSide - 1) * stride + _inputSize;
    final maxOrig = math.max(origH, origW);
    final scale = math.min(1, targetSide / maxOrig);

    final newH = math.max(_inputSize, (origH * scale).toInt());
    final newW = math.max(_inputSize, (origW * scale).toInt());

    // 缩放图像
    img.Image resized;
    if (scale < 1.0) {
      resized = img.copyResize(image, width: newW, height: newH);
      _log(
        '  缩放: ${origW}x$origH -> ${newW}x$newH '
        '(scale=${scale.toStringAsFixed(3)})',
      );
    } else {
      resized = image;
    }

    final h = resized.height;
    final w = resized.width;

    // 计算padding
    final padH = h > _inputSize
        ? (stride - (h - _inputSize) % stride) % stride
        : _inputSize - h;
    final padW = w > _inputSize
        ? (stride - (w - _inputSize) % stride) % stride
        : _inputSize - w;

    // 创建padded图像
    final paddedH = h + padH;
    final paddedW = w + padW;
    final padded = img.Image(width: paddedW, height: paddedH);

    // 复制原图到padded
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        padded.setPixel(x, y, resized.getPixel(x, y));
      }
      await _yieldDuringCpuWork(processedRows: y + 1);
    }
    // 边缘填充（反射）
    for (var y = 0; y < paddedH; y++) {
      for (var x = 0; x < paddedW; x++) {
        if (y >= h || x >= w) {
          final srcY = y >= h ? 2 * h - y - 2 : y;
          final srcX = x >= w ? 2 * w - x - 2 : x;
          final clampedY = srcY.clamp(0, h - 1);
          final clampedX = srcX.clamp(0, w - 1);
          padded.setPixel(x, y, resized.getPixel(clampedX, clampedY));
        }
      }
      await _yieldDuringCpuWork(processedRows: y + 1);
    }

    // 计算窗口数
    final nH = math.max(1, (paddedH - _inputSize) ~/ stride + 1);
    final nW = math.max(1, (paddedW - _inputSize) ~/ stride + 1);
    final total = nH * nW;

    _log('  处理尺寸: ${h}x$w -> padding后: ${paddedH}x$paddedW');
    _log('  窗口: $_inputSize, 步长: $stride, 总窗口数: $total');

    // 输出尺寸（模型输出是输入的2倍）
    const outputScale = 2;
    final outH = paddedH * outputScale;
    final outW = paddedW * outputScale;
    final outWindow = _inputSize * outputScale;

    // 初始化预测结果
    final pred = List.generate(outH, (_) => List<double>.filled(outW, 0));
    final countMap = List.generate(
      outH,
      (_) => List<double>.filled(outW, 0),
    );

    var count = 0;
    for (var i = 0; i < nH; i++) {
      for (var j = 0; j < nW; j++) {
        final y = math.min(i * stride, paddedH - _inputSize);
        final x = math.min(j * stride, paddedW - _inputSize);

        // 让出主线程，避免UI卡顿
        await _delay(Duration.zero);

        // 更新进度
        onProgress?.call(count + 1, total, '正在识别第 ${count + 1}/$total 个窗口');

        // 提取窗口并预处理
        final inputTensor = _preprocessWindow(padded, x, y);

        // ONNX推理
        final runOptions = OrtRunOptions();
        final outputs = await _runInference(
          runOptions: runOptions,
          inputTensor: inputTensor,
        );

        // 获取输出
        final outputTensor = outputs![0]! as OrtValueTensor;
        final outputData = outputTensor.value as List<List<List<List<double>>>>;

        // Sigmoid并累加
        final oy = y * outputScale;
        final ox = x * outputScale;
        for (var py = 0; py < outWindow; py++) {
          for (var px = 0; px < outWindow; px++) {
            final rawVal = outputData[0][0][py][px];
            final sigmoidVal = 1.0 / (1.0 + math.exp(-rawVal));
            pred[oy + py][ox + px] += sigmoidVal;
            countMap[oy + py][ox + px] += 1;
          }
          await _yieldDuringCpuWork(processedRows: py + 1);
        }

        // 释放资源
        inputTensor.release();
        runOptions.release();
        for (final output in outputs) {
          output?.release();
        }

        count++;
        await _yieldAfterInferenceWindow(current: count, total: total);
        if (count % 5 == 0) {
          _log('  进度: $count/$total');
        }
      }
    }

    // 平均化
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        if (countMap[y][x] > 0) {
          pred[y][x] /= countMap[y][x];
        }
      }
      await _yieldDuringCpuWork(processedRows: y + 1);
    }

    // 裁剪回缩放后尺寸
    final croppedH = h * outputScale;
    final croppedW = w * outputScale;
    final cropped = <List<double>>[];
    for (var y = 0; y < croppedH; y++) {
      cropped.add(List.generate(croppedW, (x) => pred[y][x]));
      await _yieldDuringCpuWork(processedRows: y + 1);
    }

    // 放大回原始尺寸
    return _resizePrediction(cropped, origW, origH);
  }

  Future<void> _yieldAfterInferenceWindow({
    required int current,
    required int total,
  }) async {
    if (_executionPolicy.windowCooldown > Duration.zero) {
      await _delay(_executionPolicy.windowCooldown);
      return;
    }
    await _delay(Duration.zero);
  }

  Future<void> _yieldDuringCpuWork({required int processedRows}) async {
    if (!_executionPolicy.shouldYieldAfterCpuRows(processedRows)) return;
    await _delay(_executionPolicy.cpuChunkCooldown);
  }

  /// 预处理窗口
  OrtValueTensor _preprocessWindow(img.Image image, int x, int y) {
    final data = Float32List(_inputSize * _inputSize * 3);
    var idx = 0;

    // CHW格式，ImageNet标准化
    for (var c = 0; c < 3; c++) {
      for (var py = 0; py < _inputSize; py++) {
        for (var px = 0; px < _inputSize; px++) {
          final pixel = image.getPixel(x + px, y + py);
          double value;
          if (c == 0) {
            value = pixel.r / 255.0;
          } else if (c == 1) {
            value = pixel.g / 255.0;
          } else {
            value = pixel.b / 255.0;
          }
          data[idx++] = (value - _mean[c]) / _std[c];
        }
      }
    }

    return OrtValueTensor.createTensorWithDataList(
      data,
      [1, 3, _inputSize, _inputSize],
    );
  }

  Future<List<OrtValue?>?> _runInference({
    required OrtRunOptions runOptions,
    required OrtValueTensor inputTensor,
  }) {
    final inputs = {'input': inputTensor};
    if (_useAsyncInference) {
      return _session!.runAsync(runOptions, inputs) ??
          Future<List<OrtValue?>?>.value();
    }

    return Future<List<OrtValue?>?>.value(
      _session!.run(runOptions, inputs),
    );
  }

  /// 调整预测结果尺寸
  Future<List<List<double>>> _resizePrediction(
    List<List<double>> pred,
    int targetW,
    int targetH,
  ) async {
    final srcH = pred.length;
    final srcW = pred[0].length;

    final resized = <List<double>>[];
    for (var y = 0; y < targetH; y++) {
      final srcY = (y * srcH / targetH).floor().clamp(0, srcH - 1);
      resized.add(
        List.generate(targetW, (x) {
          final srcX = (x * srcW / targetW).floor().clamp(0, srcW - 1);
          return pred[srcY][srcX];
        }),
      );
      await _yieldDuringCpuWork(processedRows: y + 1);
    }
    return resized;
  }

  /// 二值化
  Future<List<List<bool>>> _binarize(
    List<List<double>> pred,
    double threshold,
  ) async {
    final mask = <List<bool>>[];
    for (var y = 0; y < pred.length; y++) {
      mask.add(pred[y].map((v) => v > threshold).toList());
      await _yieldDuringCpuWork(processedRows: y + 1);
    }
    return mask;
  }

  /// 从mask计算裂缝占比
  Future<double> _calculateCrackRatioFromMask(List<List<bool>> mask) async {
    var crackPixels = 0;
    var totalPixels = 0;

    for (var y = 0; y < mask.length; y++) {
      final row = mask[y];
      for (final pixel in row) {
        totalPixels++;
        if (pixel) crackPixels++;
      }
      await _yieldDuringCpuWork(processedRows: y + 1);
    }

    return totalPixels > 0 ? (crackPixels / totalPixels) * 100 : 0.0;
  }

  /// 绘制分割结果（红色叠加）
  Future<Uint8List> _drawSegmentationResult(
    img.Image image,
    List<List<bool>> mask,
  ) async {
    final resultImg = img.Image.from(image);

    for (var y = 0; y < image.height && y < mask.length; y++) {
      for (var x = 0; x < image.width && x < mask[y].length; x++) {
        if (mask[y][x]) {
          // 红色半透明叠加
          final pixel = resultImg.getPixel(x, y);
          final newR = ((pixel.r + 255) / 2).toInt().clamp(0, 255);
          final newG = (pixel.g * 0.5).toInt().clamp(0, 255);
          final newB = (pixel.b * 0.5).toInt().clamp(0, 255);
          resultImg.setPixelRgb(x, y, newR, newG, newB);
        }
      }
      await _yieldDuringCpuWork(processedRows: y + 1);
    }

    return Uint8List.fromList(img.encodeJpg(resultImg));
  }

  void _releaseSession() {
    final shouldReleaseOrtEnv = _session != null || _sessionOptions != null;
    _session?.release();
    _sessionOptions?.release();
    if (shouldReleaseOrtEnv) {
      OrtEnv.instance.release();
    }
    _session = null;
    _sessionOptions = null;
  }

  /// 释放资源
  void dispose() {
    _releaseSession();
    _modelBytes = null;
    _isModelLoaded = false;
  }
}

/// 裂缝检测结果
class CrackDetectionResult {
  CrackDetectionResult({
    required this.crackRatio,
    required this.inferenceTime,
    required this.resultImage,
    required this.detectionCount,
    this.binaryMask,
    this.originalWidth = 0,
    this.originalHeight = 0,
    this.modelVersion,
    this.serverVersion,
  });
  final double crackRatio;
  final int inferenceTime;
  final Uint8List resultImage;
  final int detectionCount;

  /// 二值化裂缝掩膜（true=裂缝像素），用于 JCI 后处理
  final List<List<bool>>? binaryMask;

  /// 原始图像宽度
  final int originalWidth;

  /// 原始图像高度
  final int originalHeight;

  /// 模型版本
  final String? modelVersion;

  /// 服务器推理版本
  final String? serverVersion;
}
