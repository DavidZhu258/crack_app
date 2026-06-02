import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/binary_mask_export_service.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RLE codec roundtrips a sparse binary mask', () {
    final mask = [
      [false, false, true, true],
      [true, false, false, false],
      [true, true, true, false],
    ];

    final encoded = BinaryMaskRleCodec.encode(mask);
    final decoded = BinaryMaskRleCodec.decode(encoded);

    expect(encoded.width, 4);
    expect(encoded.height, 3);
    expect(encoded.runs, isNotEmpty);
    expect(decoded, mask);
  });

  test('export writes RLE mask JSON and copied image bytes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'crack_mask_export_test_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDir.path}/input.jpg');
    await imageFile.writeAsBytes([1, 2, 3, 4]);
    final result = CrackDetectionResult(
      crackRatio: 50,
      inferenceTime: 42,
      resultImage: Uint8List.fromList([9]),
      detectionCount: 1,
      binaryMask: [
        [true, false],
        [false, true],
      ],
      originalWidth: 2,
      originalHeight: 2,
      modelVersion: 'savss_256',
    );

    final export = await const BinaryMaskExportService().export(
      detection: result,
      sourceImagePath: imageFile.path,
      imageName: 'input.jpg',
      outputDirectory: tempDir,
      threshold: 0.3,
      maxWindows: 20,
    );

    final maskJson =
        jsonDecode(
              await File(export.maskJsonPath).readAsString(),
            )
            as Map<String, dynamic>;
    expect(maskJson['source'], 'app_offline_onnx');
    expect(maskJson['imageName'], 'input.jpg');
    expect(maskJson['modelVersion'], 'savss_256');
    expect(maskJson['width'], 2);
    expect(maskJson['height'], 2);
    expect(maskJson['binaryMaskRle'], {
      'width': 2,
      'height': 2,
      'firstValue': true,
      'runs': [1, 2, 1],
    });
    expect(await File(export.imagePath).readAsBytes(), [1, 2, 3, 4]);
  });

  test('export rejects results without a binary mask', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'crack_mask_export_missing_',
    );
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });
    final imageFile = File('${tempDir.path}/input.jpg');
    await imageFile.writeAsBytes([1]);
    final result = CrackDetectionResult(
      crackRatio: 0,
      inferenceTime: 0,
      resultImage: Uint8List(0),
      detectionCount: 0,
    );

    await expectLater(
      const BinaryMaskExportService().export(
        detection: result,
        sourceImagePath: imageFile.path,
        imageName: 'input.jpg',
        outputDirectory: tempDir,
        threshold: 0.3,
        maxWindows: 20,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
