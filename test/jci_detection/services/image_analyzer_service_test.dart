import 'dart:typed_data';

import 'package:crack_app/core/network/network_status_service.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/crack_detection/services/inference_models.dart';
import 'package:crack_app/crack_detection/services/inference_router.dart';
import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/crack_identifier_service.dart';
import 'package:crack_app/jci_detection/services/image_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/scanline_analyzer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCrackDetectionService extends Mock implements CrackDetectionService {}

class MockCrackIdentifierService extends Mock
    implements CrackIdentifierService {}

class MockScanlineAnalyzerService extends Mock
    implements ScanlineAnalyzerService {}

void main() {
  late MockCrackDetectionService mockCrackService;
  late MockCrackIdentifierService mockCrackIdentifier;
  late MockScanlineAnalyzerService mockScanlineAnalyzer;

  final testResultImage = Uint8List.fromList([1, 2, 3]);

  final testCrackResult1 = CrackDetectionResult(
    crackRatio: 10,
    inferenceTime: 100,
    resultImage: testResultImage,
    detectionCount: 1,
  );

  final testCrackResult2 = CrackDetectionResult(
    crackRatio: 20,
    inferenceTime: 150,
    resultImage: testResultImage,
    detectionCount: 1,
  );

  setUp(() {
    mockCrackService = MockCrackDetectionService();
    mockCrackIdentifier = MockCrackIdentifierService();
    mockScanlineAnalyzer = MockScanlineAnalyzerService();
  });

  group('ImageAnalyzerService - backward compatibility', () {
    test(
      'constructor works without optional dependencies',
      () {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
        );

        expect(service, isNotNull);
      },
    );

    test(
      'analyzeImages returns ExtractedParameters '
      'without extended services',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack(any()),
        ).thenAnswer((_) async => testCrackResult1);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
        );

        final result = await service.analyzeImages(
          'image1.jpg',
          'image2.jpg',
        );

        expect(result, isA<ExtractedParameters>());
        expect(result, isNot(isA<ExtractedParametersV2>()));
        expect(result.rqd, greaterThanOrEqualTo(0));
        expect(result.rqd, lessThanOrEqualTo(100));
        expect(result.jointSpacing, greaterThanOrEqualTo(0));
        expect(result.jointDensity, greaterThanOrEqualTo(0));
      },
    );

    test(
      'analyzeImages reuses detection result when both paths are the same',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack('same.jpg'),
        ).thenAnswer((_) async => testCrackResult1);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
        );

        await service.analyzeImages(
          'same.jpg',
          'same.jpg',
        );

        verify(
          () => mockCrackService.detectCrack('same.jpg'),
        ).called(1);
      },
    );

    test(
      'analyzeImages passes configured max windows to crack detector',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack(
            any(),
            maxWindows: 4,
          ),
        ).thenAnswer((_) async => testCrackResult1);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          maxInferenceWindows: 4,
        );

        await service.analyzeImages(
          'image1.jpg',
          'image2.jpg',
        );

        verify(
          () => mockCrackService.detectCrack(
            'image1.jpg',
            maxWindows: 4,
          ),
        ).called(1);
        verify(
          () => mockCrackService.detectCrack(
            'image2.jpg',
            maxWindows: 4,
          ),
        ).called(1);
      },
    );

    test(
      'analyzeImages allows per-call max windows override',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack(
            any(),
            maxWindows: 12,
          ),
        ).thenAnswer((_) async => testCrackResult1);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          maxInferenceWindows: 4,
        );

        await service.analyzeImages(
          'image1.jpg',
          'image2.jpg',
          maxInferenceWindows: 12,
        );

        verify(
          () => mockCrackService.detectCrack(
            'image1.jpg',
            maxWindows: 12,
          ),
        ).called(1);
        verify(
          () => mockCrackService.detectCrack(
            'image2.jpg',
            maxWindows: 12,
          ),
        ).called(1);
      },
    );
  });

  group('ImageAnalyzerService - remote inference', () {
    test(
      'analyzeImages uses inference router before local crack service',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(false);
        final local = _FakeInferenceClient(result: testCrackResult1);
        final remote = _FakeInferenceClient(result: testCrackResult2);
        final router = InferenceRouter(
          localClient: local,
          remoteClient: remote,
          networkStatusService: const _FakeNetworkStatusService(
            reachable: true,
          ),
        );

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          inferenceRouter: router,
          maxInferenceWindows: 4,
        );

        final result = await service.analyzeImages(
          'image1.jpg',
          'image1.jpg',
          maxInferenceWindows: 12,
        );

        expect(service.usesRemoteInference, isTrue);
        expect(remote.calls, equals(1));
        expect(remote.requests.single.imagePath, equals('image1.jpg'));
        expect(remote.requests.single.mode, equals(InferenceMode.auto));
        expect(remote.requests.single.maxWindows, equals(12));
        expect(local.calls, equals(0));
        expect(result.rqd, equals(60));
        verifyNever(() => mockCrackService.detectCrack(any()));
      },
    );

    test(
      'analyzeImages can force server highest precision for one run',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(false);
        final local = _FakeInferenceClient(result: testCrackResult1);
        final remote = _FakeInferenceClient(result: testCrackResult2);
        final router = InferenceRouter(
          localClient: local,
          remoteClient: remote,
          networkStatusService: const _FakeNetworkStatusService(
            reachable: true,
          ),
        );
        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          inferenceRouter: router,
          maxInferenceWindows: 4,
        );

        await service.analyzeImages(
          'image1.jpg',
          'image1.jpg',
          inferenceMode: InferenceMode.onlineOnly,
          maxInferenceWindows: 20,
        );

        expect(remote.requests.single.mode, equals(InferenceMode.onlineOnly));
        expect(remote.requests.single.maxWindows, equals(20));
        expect(local.calls, equals(0));
      },
    );
  });

  group('ImageAnalyzerService - with extended services', () {
    test(
      'constructor accepts optional dependencies',
      () {
        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          crackIdentifierService: mockCrackIdentifier,
          scanlineAnalyzerService: mockScanlineAnalyzer,
        );

        expect(service, isNotNull);
      },
    );

    test(
      'analyzeImages returns ExtractedParametersV2 '
      'when extended services are provided',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack('image1.jpg'),
        ).thenAnswer((_) async => testCrackResult1);
        when(
          () => mockCrackService.detectCrack('image2.jpg'),
        ).thenAnswer((_) async => testCrackResult2);

        const testCrackIdResult = CrackIdentificationResult(
          cracks: [],
          totalLengthCm: 0,
          averageLengthCm: 0,
        );

        when(
          () => mockCrackIdentifier.identifyCracks(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
          ),
        ).thenReturn(testCrackIdResult);

        const testScanlineResult = ScanlineAnalysisResult(
          scanlines: [],
          indicators: ThreeIndicators(
            indicator1: 0,
            indicator2: 0,
            indicator3: 0,
            totalCracks: 0,
            cracksAbove25cm: 0,
            totalCrackLength: 0,
            imageAreaM2: 0,
          ),
        );

        when(
          () => mockScanlineAnalyzer.analyze(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
            imageWidth: any(named: 'imageWidth'),
            imageHeight: any(named: 'imageHeight'),
            cracks: any(named: 'cracks'),
          ),
        ).thenReturn(testScanlineResult);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          crackIdentifierService: mockCrackIdentifier,
          scanlineAnalyzerService: mockScanlineAnalyzer,
        );

        final result = await service.analyzeImages(
          'image1.jpg',
          'image2.jpg',
          pixelRatio: 0.5,
        );

        expect(result, isA<ExtractedParametersV2>());

        final v2Result = result as ExtractedParametersV2;
        expect(v2Result.scanlineResult, isNotNull);
        expect(v2Result.crackResult, isNotNull);
        expect(v2Result.pixelRatio, equals(0.5));
        expect(v2Result.imageWidth, isNotNull);
        expect(v2Result.imageHeight, isNotNull);
      },
    );

    test(
      'analyzeImages calls crack identifier and scanline analyzer',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack(any()),
        ).thenAnswer((_) async => testCrackResult1);

        const testCrackIdResult = CrackIdentificationResult(
          cracks: [],
          totalLengthCm: 0,
          averageLengthCm: 0,
        );

        when(
          () => mockCrackIdentifier.identifyCracks(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
          ),
        ).thenReturn(testCrackIdResult);

        const testScanlineResult = ScanlineAnalysisResult(
          scanlines: [],
          indicators: ThreeIndicators(
            indicator1: 0,
            indicator2: 0,
            indicator3: 0,
            totalCracks: 0,
            cracksAbove25cm: 0,
            totalCrackLength: 0,
            imageAreaM2: 0,
          ),
        );

        when(
          () => mockScanlineAnalyzer.analyze(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
            imageWidth: any(named: 'imageWidth'),
            imageHeight: any(named: 'imageHeight'),
            cracks: any(named: 'cracks'),
          ),
        ).thenReturn(testScanlineResult);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          crackIdentifierService: mockCrackIdentifier,
          scanlineAnalyzerService: mockScanlineAnalyzer,
        );

        await service.analyzeImages(
          'image1.jpg',
          'image2.jpg',
        );

        verify(
          () => mockCrackIdentifier.identifyCracks(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
          ),
        ).called(1);

        verify(
          () => mockScanlineAnalyzer.analyze(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
            imageWidth: any(named: 'imageWidth'),
            imageHeight: any(named: 'imageHeight'),
            cracks: any(named: 'cracks'),
          ),
        ).called(1);
      },
    );

    test(
      'analyzeImages uses default pixel ratio when not provided',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);
        when(
          () => mockCrackService.detectCrack(any()),
        ).thenAnswer((_) async => testCrackResult1);

        const testCrackIdResult = CrackIdentificationResult(
          cracks: [],
          totalLengthCm: 0,
          averageLengthCm: 0,
        );

        when(
          () => mockCrackIdentifier.identifyCracks(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
          ),
        ).thenReturn(testCrackIdResult);

        const testScanlineResult = ScanlineAnalysisResult(
          scanlines: [],
          indicators: ThreeIndicators(
            indicator1: 0,
            indicator2: 0,
            indicator3: 0,
            totalCracks: 0,
            cracksAbove25cm: 0,
            totalCrackLength: 0,
            imageAreaM2: 0,
          ),
        );

        when(
          () => mockScanlineAnalyzer.analyze(
            crackMask: any(named: 'crackMask'),
            pixelRatio: any(named: 'pixelRatio'),
            imageWidth: any(named: 'imageWidth'),
            imageHeight: any(named: 'imageHeight'),
            cracks: any(named: 'cracks'),
          ),
        ).thenReturn(testScanlineResult);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
          crackIdentifierService: mockCrackIdentifier,
          scanlineAnalyzerService: mockScanlineAnalyzer,
        );

        final result = await service.analyzeImages(
          'image1.jpg',
          'image2.jpg',
        );

        final v2Result = result as ExtractedParametersV2;
        expect(v2Result.pixelRatio, equals(1.0));
      },
    );
  });

  group('ImageAnalyzerService - error handling', () {
    test(
      'throws when model not loaded',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(false);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
        );

        expect(
          () => service.analyzeImages('image1.jpg', 'image2.jpg'),
          throwsA(isA<ImageAnalysisException>()),
        );
      },
    );

    test(
      'throws when image quality is poor',
      () async {
        when(() => mockCrackService.isModelLoaded).thenReturn(true);

        final poorResult = CrackDetectionResult(
          crackRatio: 90,
          inferenceTime: 100,
          resultImage: testResultImage,
          detectionCount: 1,
        );

        when(
          () => mockCrackService.detectCrack(any()),
        ).thenAnswer((_) async => poorResult);

        final service = ImageAnalyzerService(
          crackService: mockCrackService,
        );

        expect(
          () => service.analyzeImages('image1.jpg', 'image2.jpg'),
          throwsA(isA<ImageAnalysisException>()),
        );
      },
    );
  });

  group('ExtractedParametersV2', () {
    test('is a subtype of ExtractedParameters', () {
      final v2 = ExtractedParametersV2(
        rqd: 80,
        jointSpacing: 1.5,
        jointDensity: 5,
        resultImage1: testResultImage,
        resultImage2: testResultImage,
      );

      expect(v2, isA<ExtractedParameters>());
    });

    test('can be used where ExtractedParameters is expected', () {
      final v2 = ExtractedParametersV2(
        rqd: 80,
        jointSpacing: 1.5,
        jointDensity: 5,
        resultImage1: testResultImage,
        resultImage2: testResultImage,
        pixelRatio: 0.5,
        imageWidth: 800,
        imageHeight: 600,
      );

      // Can be assigned to ExtractedParameters variable
      final ExtractedParameters params = v2;
      expect(params.rqd, equals(80));
      expect(params.jointSpacing, equals(1.5));
      expect(params.jointDensity, equals(5));
    });

    test('optional fields default to null', () {
      final v2 = ExtractedParametersV2(
        rqd: 80,
        jointSpacing: 1.5,
        jointDensity: 5,
        resultImage1: testResultImage,
        resultImage2: testResultImage,
      );

      expect(v2.scanlineResult, isNull);
      expect(v2.crackResult, isNull);
      expect(v2.pixelRatio, isNull);
      expect(v2.imageWidth, isNull);
      expect(v2.imageHeight, isNull);
    });

    test('copyWithV2 preserves all fields', () {
      const scanlineResult = ScanlineAnalysisResult(
        scanlines: [],
        indicators: ThreeIndicators(
          indicator1: 1,
          indicator2: 2,
          indicator3: 3,
          totalCracks: 10,
          cracksAbove25cm: 5,
          totalCrackLength: 100,
          imageAreaM2: 4,
        ),
      );

      final v2 = ExtractedParametersV2(
        rqd: 80,
        jointSpacing: 1.5,
        jointDensity: 5,
        resultImage1: testResultImage,
        resultImage2: testResultImage,
        scanlineResult: scanlineResult,
        pixelRatio: 0.5,
        imageWidth: 800,
        imageHeight: 600,
      );

      final copy = v2.copyWithV2(rqd: 90);

      expect(copy.rqd, equals(90));
      expect(copy.jointSpacing, equals(1.5));
      expect(copy.scanlineResult, equals(scanlineResult));
      expect(copy.pixelRatio, equals(0.5));
      expect(copy.imageWidth, equals(800));
      expect(copy.imageHeight, equals(600));
    });

    test('equality works correctly', () {
      final v2a = ExtractedParametersV2(
        rqd: 80,
        jointSpacing: 1.5,
        jointDensity: 5,
        resultImage1: testResultImage,
        resultImage2: testResultImage,
        pixelRatio: 0.5,
      );

      final v2b = ExtractedParametersV2(
        rqd: 80,
        jointSpacing: 1.5,
        jointDensity: 5,
        resultImage1: testResultImage,
        resultImage2: testResultImage,
        pixelRatio: 0.5,
      );

      expect(v2a, equals(v2b));
    });
  });
}

class _FakeNetworkStatusService implements NetworkStatusService {
  const _FakeNetworkStatusService({required this.reachable});

  final bool reachable;

  @override
  Future<bool> canReachServer() async => reachable;
}

class _FakeInferenceClient implements InferenceClient {
  _FakeInferenceClient({required this.result});

  final CrackDetectionResult result;
  final requests = <InferenceRequest>[];

  int get calls => requests.length;

  @override
  Future<CrackDetectionResult> detect(InferenceRequest request) async {
    requests.add(request);
    return result;
  }
}
