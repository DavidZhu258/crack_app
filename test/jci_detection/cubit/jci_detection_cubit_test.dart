import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_cubit.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_state.dart';
import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/models/standard_image_option.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/image_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockImageAnalyzerService extends Mock implements ImageAnalyzerService {}

class MockCrackDetectionService extends Mock implements CrackDetectionService {}

class MockJciStorageService extends Mock implements JciStorageService {}

class MockImagePicker extends Mock implements ImagePicker {}

class FakeJciDetectionResult extends Fake implements JciDetectionResult {}

void main() {
  late MockImageAnalyzerService imageAnalyzerService;
  late MockCrackDetectionService crackService;
  late MockJciStorageService storageService;
  late MockImagePicker imagePicker;

  setUpAll(() {
    registerFallbackValue(FakeJciDetectionResult());
  });

  setUp(() {
    imageAnalyzerService = MockImageAnalyzerService();
    crackService = MockCrackDetectionService();
    storageService = MockJciStorageService();
    imagePicker = MockImagePicker();

    when(() => crackService.isModelLoaded).thenReturn(true);
    when(() => imageAnalyzerService.usesRemoteInference).thenReturn(false);
    when(() => storageService.saveResult(any())).thenAnswer((_) async {});
  });

  test('分析等待状态覆盖离线识别、在线识别和在线回退文案', () {
    expect(
      const JciDetectionAnalyzing(
        currentStep: 'offline_detecting',
        progress: 0.1,
      ).currentStepDescription,
      equals('正在进行离线识别...'),
    );
    expect(
      const JciDetectionAnalyzing(
        currentStep: 'preparing_online_detection',
        progress: 0.05,
      ).currentStepDescription,
      equals('正在准备服务器在线识别...'),
    );
    expect(
      const JciDetectionAnalyzing(
        currentStep: 'online_detecting',
        progress: 0.1,
      ).currentStepDescription,
      equals('正在等待服务器在线识别...'),
    );
    expect(
      const JciDetectionAnalyzing(
        currentStep: 'online_fallback',
        progress: 0.1,
      ).currentStepDescription,
      equals('在线识别失败，正在切换离线识别...'),
    );
  });

  test('标准样图列表提供三张并排除旧默认图', () {
    expect(jciStandardImageOptions, hasLength(3));
    expect(
      jciStandardImageOptions.map((option) => option.assetPath),
      isNot(contains('assets/images/test/1.jpg')),
    );
  });

  test('兼容默认入口加载第一张标准样图而不是旧默认图', () async {
    when(
      () => crackService.loadTestImageFromAssets(any()),
    ).thenAnswer((invocation) async {
      return invocation.positionalArguments.single! as String;
    });

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      waitBeforeRecognition: () async {},
    );

    await cubit.loadTestImages();

    final selected = cubit.state as JciDetectionImagesSelected;
    expect(selected.image1Path, equals('assets/images/test/0_slide.jpg'));
    expect(selected.image2Path, equals('assets/images/test/0_slide.jpg'));
    verify(
      () => crackService.loadTestImageFromAssets(
        'assets/images/test/0_slide.jpg',
      ),
    ).called(1);
    verifyNever(
      () => crackService.loadTestImageFromAssets('assets/images/test/1.jpg'),
    );
  });

  test('可按用户选择加载指定标准样图', () async {
    when(
      () => crackService.loadTestImageFromAssets(
        'assets/images/test/14.jpg',
      ),
    ).thenAnswer((_) async => 'tmp/standard-2.jpg');

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      waitBeforeRecognition: () async {},
    );

    await cubit.loadStandardImage(jciStandardImageOptions[1]);

    final selected = cubit.state as JciDetectionImagesSelected;
    expect(selected.image1Path, equals('tmp/standard-2.jpg'));
    expect(selected.image2Path, equals('tmp/standard-2.jpg'));
  });

  test('单张识别图像即可分析，并把金川岩性 UCS 与真实三大指标传入 JCI', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    const indicators = ThreeIndicators(
      indicator1: 0.75,
      indicator2: 80,
      indicator3: 0.8,
      totalCracks: 3,
      cracksAbove25cm: 2,
      totalCrackLength: 120,
      imageAreaM2: 1.5,
    );
    final extractedParams = ExtractedParametersV2(
      rqd: 80,
      jointSpacing: 1.5,
      jointDensity: 0.8,
      resultImage1: Uint8List.fromList([1, 2, 3]),
      resultImage2: Uint8List.fromList([1, 2, 3]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: indicators,
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 120,
        averageLengthCm: 40,
      ),
      imageWidth: 100,
      imageHeight: 100,
      pixelRatio: 1,
    );

    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      idGenerator: () => 'fixed_id',
    );

    await cubit.selectImage(1, ImageSource.gallery);
    expect(
      (cubit.state as JciDetectionImagesSelected).canStartAnalysis,
      isTrue,
    );

    await cubit.startAnalysis(
      const EngineeringInfo(
        rockType: RockType.serpentineMarble,
        depth: 598,
        waterCondition: WaterCondition.dry,
      ),
    );

    final success = cubit.state as JciDetectionSuccess;
    expect(success.result.image1Path, equals(imagePath));
    expect(success.result.image2Path, equals(imagePath));
    expect(success.result.scanlineResult!.indicators, equals(indicators));
    expect(
      success.result.jciResult.componentScores['indicator1'],
      equals(0.75),
    );
    expect(success.result.jciResult.componentScores['indicator2'], equals(80));
    expect(success.result.jciResult.componentScores['indicator3'], equals(0.8));
    expect(
      success.result.jciResult.componentScores['UCS'],
      equals(RockType.serpentineMarble.ucsMpa),
    );

    verify(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).called(1);
    verify(() => storageService.saveResult(any())).called(1);
  });

  test('默认检测流程会生成本地报告文件并写入记录路径', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    final extractedParams = ExtractedParametersV2(
      rqd: 80,
      jointSpacing: 1.5,
      jointDensity: 0.8,
      resultImage1: Uint8List.fromList([1, 2, 3]),
      resultImage2: Uint8List.fromList([1, 2, 3]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 0.75,
          indicator2: 80,
          indicator3: 0.8,
          totalCracks: 3,
          cracksAbove25cm: 2,
          totalCrackLength: 120,
          imageAreaM2: 1.5,
        ),
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 120,
        averageLengthCm: 40,
      ),
      imageWidth: 100,
      imageHeight: 100,
      pixelRatio: 1,
    );
    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      idGenerator: () => 'report_id',
      waitBeforeRecognition: () async {},
    );

    await cubit.selectImage(1, ImageSource.gallery);
    await cubit.startAnalysis(
      const EngineeringInfo(
        rockType: RockType.serpentineMarble,
        depth: 598,
        waterCondition: WaterCondition.dry,
      ),
    );

    final result = (cubit.state as JciDetectionSuccess).result;
    expect(result.reportPath, isNotNull);
    expect(File(result.reportPath!).existsSync(), isTrue);
    expect(
      File(result.reportPath!).readAsStringSync(),
      contains('裂缝长度测量报告'),
    );
  });

  test('可先完成图像识别并展示真实三大指标，无需先填写工程信息', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    const indicators = ThreeIndicators(
      indicator1: 1.25,
      indicator2: 64,
      indicator3: 0.42,
      totalCracks: 4,
      cracksAbove25cm: 3,
      totalCrackLength: 96,
      imageAreaM2: 2.4,
    );
    final extractedParams = ExtractedParametersV2(
      rqd: 75,
      jointSpacing: 1.2,
      jointDensity: 0.42,
      resultImage1: Uint8List.fromList([4, 5, 6]),
      resultImage2: Uint8List.fromList([4, 5, 6]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: indicators,
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 96,
        averageLengthCm: 24,
      ),
      imageWidth: 120,
      imageHeight: 80,
      pixelRatio: 1,
    );

    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      waitBeforeRecognition: () async {},
    );

    await cubit.selectImage(1, ImageSource.gallery);
    await cubit.recognizeImages();

    final ready = cubit.state as JciDetectionParametersReady;
    expect(ready.image1Path, equals(imagePath));
    expect(ready.image2Path, equals(imagePath));
    expect(ready.extractedParams, same(extractedParams));
    expect(ready.scanlineResult!.indicators, equals(indicators));
    verifyNever(() => storageService.saveResult(any()));
  });

  test('图像识别会把本次选择的窗口数量传给分析服务', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    final extractedParams = ExtractedParametersV2(
      rqd: 75,
      jointSpacing: 1.2,
      jointDensity: 0.42,
      resultImage1: Uint8List.fromList([4, 5, 6]),
      resultImage2: Uint8List.fromList([4, 5, 6]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 1.25,
          indicator2: 64,
          indicator3: 0.42,
          totalCracks: 4,
          cracksAbove25cm: 3,
          totalCrackLength: 96,
          imageAreaM2: 2.4,
        ),
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 96,
        averageLengthCm: 24,
      ),
      imageWidth: 120,
      imageHeight: 80,
      pixelRatio: 1,
    );

    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
        maxInferenceWindows: 12,
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
    );

    await cubit.selectImage(1, ImageSource.gallery);
    await cubit.recognizeImages(maxInferenceWindows: 12);

    expect(cubit.state, isA<JciDetectionParametersReady>());
    verify(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
        maxInferenceWindows: 12,
      ),
    ).called(1);
  });

  test('图像识别等待状态明确显示离线识别步骤', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    const indicators = ThreeIndicators(
      indicator1: 1.25,
      indicator2: 64,
      indicator3: 0.42,
      totalCracks: 4,
      cracksAbove25cm: 3,
      totalCrackLength: 96,
      imageAreaM2: 2.4,
    );
    final extractedParams = ExtractedParametersV2(
      rqd: 75,
      jointSpacing: 1.2,
      jointDensity: 0.42,
      resultImage1: Uint8List.fromList([4, 5, 6]),
      resultImage2: Uint8List.fromList([4, 5, 6]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: indicators,
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 96,
        averageLengthCm: 24,
      ),
      imageWidth: 120,
      imageHeight: 80,
      pixelRatio: 1,
    );

    final analysisGate = Completer<ExtractedParameters>();
    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) => analysisGate.future);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      waitBeforeRecognition: () async {},
    );

    await cubit.selectImage(1, ImageSource.gallery);
    final task = cubit.recognizeImages();
    await Future<void>.delayed(Duration.zero);

    final analyzing = cubit.state as JciDetectionAnalyzing;
    expect(analyzing.currentStep, equals('offline_detecting'));
    expect(analyzing.currentStepDescription, equals('正在进行离线识别...'));
    expect(analyzing.progress, equals(0.1));

    analysisGate.complete(extractedParams);
    await task;
    expect(cubit.state, isA<JciDetectionParametersReady>());
  });

  test('远程推理入口启用时图像识别显示服务器在线识别状态', () async {
    const imagePath = 'face.jpg';
    when(() => imageAnalyzerService.usesRemoteInference).thenReturn(true);
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    final extractedParams = ExtractedParametersV2(
      rqd: 75,
      jointSpacing: 1.2,
      jointDensity: 0.42,
      resultImage1: Uint8List.fromList([4, 5, 6]),
      resultImage2: Uint8List.fromList([4, 5, 6]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 1.25,
          indicator2: 64,
          indicator3: 0.42,
          totalCracks: 4,
          cracksAbove25cm: 3,
          totalCrackLength: 96,
          imageAreaM2: 2.4,
        ),
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 96,
        averageLengthCm: 24,
      ),
      imageWidth: 120,
      imageHeight: 80,
      pixelRatio: 1,
    );

    final analysisGate = Completer<ExtractedParameters>();
    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) => analysisGate.future);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      waitBeforeRecognition: () async {},
    );

    await cubit.selectImage(1, ImageSource.gallery);
    final task = cubit.recognizeImages();
    await Future<void>.delayed(Duration.zero);

    final analyzing = cubit.state as JciDetectionAnalyzing;
    expect(analyzing.currentStep, equals('online_detecting'));
    expect(analyzing.currentStepDescription, equals('正在等待服务器在线识别...'));
    expect(analyzing.progress, equals(0.1));

    analysisGate.complete(extractedParams);
    await task;
    expect(cubit.state, isA<JciDetectionParametersReady>());
  });

  test('图像识别会先等待 UI 渲染再调用模型分析', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    final extractedParams = ExtractedParametersV2(
      rqd: 75,
      jointSpacing: 1.2,
      jointDensity: 0.42,
      resultImage1: Uint8List.fromList([4, 5, 6]),
      resultImage2: Uint8List.fromList([4, 5, 6]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 1.25,
          indicator2: 64,
          indicator3: 0.42,
          totalCracks: 4,
          cracksAbove25cm: 3,
          totalCrackLength: 96,
          imageAreaM2: 2.4,
        ),
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 96,
        averageLengthCm: 24,
      ),
      imageWidth: 120,
      imageHeight: 80,
      pixelRatio: 1,
    );

    final waitGate = Completer<void>();
    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      waitBeforeRecognition: () => waitGate.future,
    );

    await cubit.selectImage(1, ImageSource.gallery);
    final task = cubit.recognizeImages();
    await Future<void>.delayed(Duration.zero);

    final analyzing = cubit.state as JciDetectionAnalyzing;
    expect(analyzing.currentStep, equals('preparing_offline_detection'));
    expect(analyzing.currentStepDescription, equals('正在准备离线模型识别...'));
    verifyNever(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    );

    waitGate.complete();
    await task;

    expect(cubit.state, isA<JciDetectionParametersReady>());
    verify(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).called(1);
  });

  test('工程信息录入后复用已识别指标计算并自动保存', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    const indicators = ThreeIndicators(
      indicator1: 0.75,
      indicator2: 80,
      indicator3: 0.8,
      totalCracks: 3,
      cracksAbove25cm: 2,
      totalCrackLength: 120,
      imageAreaM2: 1.5,
    );
    final extractedParams = ExtractedParametersV2(
      rqd: 80,
      jointSpacing: 1.5,
      jointDensity: 0.8,
      resultImage1: Uint8List.fromList([1, 2, 3]),
      resultImage2: Uint8List.fromList([1, 2, 3]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: indicators,
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 120,
        averageLengthCm: 40,
      ),
      imageWidth: 100,
      imageHeight: 100,
      pixelRatio: 1,
    );

    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      idGenerator: () => 'fixed_id',
    );

    await cubit.selectImage(1, ImageSource.gallery);
    await cubit.recognizeImages();
    await cubit.calculateWithEngineeringInfo(
      const EngineeringInfo(
        rockType: RockType.serpentineMarble,
        depth: 598,
        waterCondition: WaterCondition.dry,
        location: '二矿598',
        projectName: '水泵房',
        inspector: '张三',
        hasSeepage: true,
      ),
    );

    final success = cubit.state as JciDetectionSuccess;
    expect(success.result.id, equals('fixed_id'));
    expect(success.result.engineeringInfo.projectName, equals('水泵房'));
    expect(success.result.engineeringInfo.projectLocation, equals('二矿598'));
    expect(success.result.engineeringInfo.workerName, equals('张三'));
    expect(success.result.engineeringInfo.elevation, equals(598));
    expect(success.result.scanlineResult!.indicators, equals(indicators));
    expect(
      success.result.jciResult.componentScores['UCS'],
      equals(RockType.serpentineMarble.ucsMpa),
    );

    verify(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).called(1);
    verify(() => storageService.saveResult(any())).called(1);
  });

  test('人工不接受识别结果时记录人工等级和人工支护方案', () async {
    const imagePath = 'face.jpg';
    when(
      () => imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) async => XFile(imagePath));

    const indicators = ThreeIndicators(
      indicator1: 0.75,
      indicator2: 80,
      indicator3: 0.8,
      totalCracks: 3,
      cracksAbove25cm: 2,
      totalCrackLength: 120,
      imageAreaM2: 1.5,
    );
    final extractedParams = ExtractedParametersV2(
      rqd: 80,
      jointSpacing: 1.5,
      jointDensity: 0.8,
      resultImage1: Uint8List.fromList([1, 2, 3]),
      resultImage2: Uint8List.fromList([1, 2, 3]),
      scanlineResult: const ScanlineAnalysisResult(
        scanlines: [],
        indicators: indicators,
      ),
      crackResult: const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 120,
        averageLengthCm: 40,
      ),
      imageWidth: 100,
      imageHeight: 100,
      pixelRatio: 1,
    );
    when(
      () => imageAnalyzerService.analyzeImages(
        imagePath,
        imagePath,
        pixelRatio: any(named: 'pixelRatio'),
      ),
    ).thenAnswer((_) async => extractedParams);

    final cubit = JciDetectionCubit(
      imageAnalyzerService: imageAnalyzerService,
      crackService: crackService,
      jciStorageService: storageService,
      imagePicker: imagePicker,
      idGenerator: () => 'manual_id',
    );

    await cubit.selectImage(1, ImageSource.gallery);
    await cubit.startAnalysis(
      const EngineeringInfo(
        rockType: RockType.granite,
        depth: 598,
        waterCondition: WaterCondition.dry,
        inspector: '张三',
      ),
    );
    final calculated = (cubit.state as JciDetectionSuccess).result;
    const manualPlan = SupportPlan(
      grade: RockGrade.iv,
      methods: [
        SupportMethod(
          name: '人工选择支护',
          parameters: {'支护等级': 'IV'},
        ),
      ],
      summary: '人工选择 IV 类支护方案',
    );

    await cubit.submitManualReview(
      ManualReview(
        acceptedRecognitionResult: false,
        manualGrade: RockGrade.iv,
        selectedSupportPlan: manualPlan,
        reviewerName: '王工',
        note: '现场破碎带更发育',
        reviewedAt: DateTime.utc(2026, 5, 7, 9, 30),
      ),
    );

    final success = cubit.state as JciDetectionSuccess;
    expect(success.result.id, equals(calculated.id));
    expect(success.result.manualReview, isNotNull);
    expect(success.result.manualReview!.acceptedRecognitionResult, isFalse);
    expect(success.result.manualReview!.manualGrade, equals(RockGrade.iv));
    expect(success.result.effectiveGrade, equals(RockGrade.iv));
    expect(success.result.effectiveSupportPlan.grade, equals(RockGrade.iv));
    expect(success.result.syncStatus, equals(SyncStatus.pendingUpload));
    expect(success.result.reportPath, isNotNull);
    final report = File(success.result.reportPath!).readAsStringSync();
    expect(report, contains('人工采用等级: IV - 差'));
    expect(report, contains('人工选择 IV 类支护方案'));
    expect(report, contains('现场破碎带更发育'));
    verify(() => storageService.saveResult(any())).called(2);
  });
}
