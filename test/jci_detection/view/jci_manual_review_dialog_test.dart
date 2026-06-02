import 'dart:convert';
import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_cubit.dart';
import 'package:crack_app/jci_detection/cubit/jci_detection_state.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/image_analyzer_service.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';
import 'package:crack_app/jci_detection/view/jci_detection_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockImageAnalyzerService extends Mock implements ImageAnalyzerService {}

class _MockCrackDetectionService extends Mock
    implements CrackDetectionService {}

class _MockJciStorageService extends Mock implements JciStorageService {}

class _FakeJciDetectionResult extends Fake implements JciDetectionResult {}

class _ResultCubit extends JciDetectionCubit {
  _ResultCubit({
    required super.imageAnalyzerService,
    required super.crackService,
    required JciStorageService storageService,
  }) : super(jciStorageService: storageService);

  void showResult(JciDetectionResult result) {
    emit(JciDetectionSuccess(result: result));
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeJciDetectionResult());
  });

  testWidgets('manual review only asks for grade and derives support plan', (
    tester,
  ) async {
    final storage = _MockJciStorageService();
    when(() => storage.saveResult(any())).thenAnswer((_) async {});

    final crackService = _MockCrackDetectionService();
    when(() => crackService.isModelLoaded).thenReturn(true);

    final cubit = _ResultCubit(
      imageAnalyzerService: _MockImageAnalyzerService(),
      crackService: crackService,
      storageService: storage,
    )..showResult(_resultWithMismatchedSupport());

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<JciDetectionCubit>.value(
          value: cubit,
          child: const JciDetectionView(),
        ),
      ),
    );

    await tester.ensureVisible(find.text('人工调整'));
    await tester.tap(find.text('人工调整'));
    await tester.pumpAndSettle();

    expect(find.text('人工判断级别'), findsOneWidget);
    expect(find.text('人工支护方案'), findsNothing);
    expect(find.textContaining('IV类围岩差'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<RockGrade>));
    await tester.pumpAndSettle();

    expect(find.textContaining('I-1类围岩极好'), findsOneWidget);
    expect(find.textContaining('V类围岩极差'), findsOneWidget);

    await tester.tap(find.textContaining('IV类围岩差').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final state = cubit.state as JciDetectionSuccess;
    final review = state.result.manualReview;
    expect(review, isNotNull);
    expect(review!.manualGrade, equals(RockGrade.iv));
    expect(review.selectedSupportPlan?.grade, equals(RockGrade.iv));
    expect(state.result.effectiveSupportPlan.grade, equals(RockGrade.iv));
  });
}

JciDetectionResult _resultWithMismatchedSupport() {
  final bytes = _tinyPng();
  return JciDetectionResult(
    id: 'manual-ui-record',
    timestamp: DateTime.utc(2026, 5, 11, 8),
    image1Path: '/tmp/front.jpg',
    image2Path: '/tmp/front.jpg',
    resultImage1: bytes,
    resultImage2: bytes,
    extractedParams: ExtractedParameters(
      rqd: 80,
      jointSpacing: 20,
      jointDensity: 1,
      resultImage1: bytes,
      resultImage2: bytes,
    ),
    engineeringInfo: const EngineeringInfo(
      rockType: RockType.granite,
      depth: 598,
      waterCondition: WaterCondition.dry,
      inspector: '张三',
    ),
    jciResult: const JciCalculationResult(
      jciValue: 35,
      componentScores: {},
    ),
    classification: const RockClassificationResult(
      originalGrade: RockGrade.iv,
      finalGrade: RockGrade.iv,
    ),
    supportPlan: const SupportPlan(
      grade: RockGrade.ii1,
      methods: [],
      summary: '旧支护方案',
    ),
    syncStatus: SyncStatus.uploaded,
  );
}

Uint8List _tinyPng() {
  return base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
  );
}
