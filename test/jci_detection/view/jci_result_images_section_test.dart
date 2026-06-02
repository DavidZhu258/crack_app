import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/view/jci_result_images_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('单图 JCI 结果只展示掌子面识别结果图', (tester) async {
    await tester.pumpWidget(_host(_record()));

    expect(find.text('检测结果图像'), findsOneWidget);
    expect(find.text('掌子面识别结果图'), findsOneWidget);
    expect(find.text('掌子面图像1'), findsNothing);
    expect(find.text('掌子面图像2'), findsNothing);
    expect(find.text('历史兼容图像2'), findsNothing);
  });

  testWidgets('旧双图 JCI 结果用历史兼容文案展示第二图', (tester) async {
    await tester.pumpWidget(_host(_record(image2Path: '/tmp/legacy-b.jpg')));

    expect(find.text('掌子面识别结果图'), findsOneWidget);
    expect(find.text('历史兼容图像2'), findsOneWidget);
    expect(find.text('掌子面图像1'), findsNothing);
    expect(find.text('掌子面图像2'), findsNothing);
  });
}

Widget _host(JciDetectionResult result) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: JciResultImagesSection(result: result),
      ),
    ),
  );
}

JciDetectionResult _record({String image2Path = '/tmp/front-face.jpg'}) {
  final bytes = _onePixelPng();
  return JciDetectionResult(
    id: 'r1',
    timestamp: DateTime.utc(2026, 5, 11),
    image1Path: '/tmp/front-face.jpg',
    image2Path: image2Path,
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
    ),
    jciResult: const JciCalculationResult(
      jciValue: 35,
      componentScores: {},
    ),
    classification: const RockClassificationResult(
      originalGrade: RockGrade.ii1,
      finalGrade: RockGrade.ii1,
    ),
    supportPlan: const SupportPlan(
      grade: RockGrade.ii1,
      methods: [],
      summary: '算法匹配 II-1 支护',
    ),
  );
}

Uint8List _onePixelPng() {
  return Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
}
