import 'dart:convert';
import 'dart:io';

import 'package:crack_app/crack_detection/services/binary_mask_export_service.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

const _imageAsset = String.fromEnvironment(
  'CRACK_EXPORT_IMAGE_ASSET',
  defaultValue: 'assets/images/test/1.jpg',
);
const String _thresholdValue = String.fromEnvironment(
  'CRACK_EXPORT_THRESHOLD',
  defaultValue: '0.3',
);
const String _maxWindowsValue = String.fromEnvironment(
  'CRACK_EXPORT_MAX_WINDOWS',
  defaultValue: '20',
);
const String _holdSecondsValue = String.fromEnvironment(
  'CRACK_EXPORT_HOLD_SECONDS',
  defaultValue: '0',
);
final double _threshold = double.parse(_thresholdValue);
final int _maxWindows = int.parse(_maxWindowsValue);
final int _holdSeconds = int.parse(_holdSecondsValue);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exports real app ONNX binaryMask for server comparison', (
    tester,
  ) async {
    final exportDirectory = await _exportDirectory();
    final imageFile = await _writeComparisonImage(exportDirectory);
    final service = CrackDetectionService();

    try {
      await service.loadModel();
      final detection = await service.detectCrack(
        imageFile.path,
        threshold: _threshold,
        maxWindows: _maxWindows,
      );
      final export = await const BinaryMaskExportService().export(
        detection: detection,
        sourceImagePath: imageFile.path,
        imageName: imageFile.uri.pathSegments.last,
        outputDirectory: exportDirectory,
        threshold: _threshold,
        maxWindows: _maxWindows,
      );
      final summary = {
        'maskJsonPath': export.maskJsonPath,
        'imagePath': export.imagePath,
        'width': detection.originalWidth,
        'height': detection.originalHeight,
        'crackRatio': detection.crackRatio,
        'modelVersion': detection.modelVersion,
      };
      // The host runner reads this line to pull the files with adb.
      // ignore: avoid_print
      print('CRACK_BINARY_MASK_EXPORT=${jsonEncode(summary)}');

      expect(File(export.maskJsonPath).existsSync(), isTrue);
      expect(File(export.imagePath).existsSync(), isTrue);
      expect(detection.binaryMask, isNotNull);
      expect(detection.originalWidth, greaterThan(0));
      expect(detection.originalHeight, greaterThan(0));
      if (_holdSeconds > 0) {
        await Future<void>.delayed(Duration(seconds: _holdSeconds));
      }
    } finally {
      service.dispose();
    }
  });
}

Future<Directory> _exportDirectory() async {
  final base =
      await getExternalStorageDirectory() ?? await getTemporaryDirectory();
  final directory = Directory('${base.path}/crack_mask_exports');
  if (!directory.existsSync()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<File> _writeComparisonImage(Directory directory) async {
  final bytes = (await rootBundle.load(_imageAsset)).buffer.asUint8List();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('Cannot decode $_imageAsset');
  }
  const maxDimension = 800;
  var comparisonImage = decoded;
  if (decoded.width > maxDimension || decoded.height > maxDimension) {
    final scale =
        maxDimension /
        (decoded.width > decoded.height ? decoded.width : decoded.height);
    comparisonImage = img.copyResize(
      decoded,
      width: (decoded.width * scale).toInt(),
      height: (decoded.height * scale).toInt(),
    );
  }
  final file = File('${directory.path}/app_onnx_comparison_image.jpg');
  await file.writeAsBytes(
    img.encodeJpg(comparisonImage, quality: 95),
    flush: true,
  );
  return file;
}
