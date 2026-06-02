import 'dart:convert';
import 'dart:io';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';

class BinaryMaskRle {
  const BinaryMaskRle({
    required this.width,
    required this.height,
    required this.firstValue,
    required this.runs,
  });

  factory BinaryMaskRle.fromJson(Map<String, dynamic> json) {
    return BinaryMaskRle(
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
      firstValue: json['firstValue'] == true,
      runs: (json['runs'] as List<dynamic>? ?? const [])
          .map((value) => (value as num).toInt())
          .toList(),
    );
  }

  final int width;
  final int height;
  final bool firstValue;
  final List<int> runs;

  Map<String, dynamic> toJson() {
    return {
      'width': width,
      'height': height,
      'firstValue': firstValue,
      'runs': runs,
    };
  }
}

class BinaryMaskRleCodec {
  const BinaryMaskRleCodec._();

  static BinaryMaskRle encode(List<List<bool>> mask) {
    final height = mask.length;
    final width = mask.fold<int>(
      0,
      (current, row) => row.length > current ? row.length : current,
    );
    if (height == 0 || width == 0) {
      return const BinaryMaskRle(
        width: 0,
        height: 0,
        firstValue: false,
        runs: [],
      );
    }

    final firstValue = _valueAt(mask, 0, 0);
    var currentValue = firstValue;
    var currentRun = 0;
    final runs = <int>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final value = _valueAt(mask, x, y);
        if (value == currentValue) {
          currentRun++;
        } else {
          runs.add(currentRun);
          currentValue = value;
          currentRun = 1;
        }
      }
    }
    runs.add(currentRun);
    return BinaryMaskRle(
      width: width,
      height: height,
      firstValue: firstValue,
      runs: runs,
    );
  }

  static List<List<bool>> decode(BinaryMaskRle rle) {
    if (rle.width <= 0 || rle.height <= 0) {
      return [];
    }
    final flat = <bool>[];
    var value = rle.firstValue;
    for (final run in rle.runs) {
      flat.addAll(List<bool>.filled(run, value));
      value = !value;
    }
    final expected = rle.width * rle.height;
    if (flat.length < expected) {
      flat.addAll(List<bool>.filled(expected - flat.length, false));
    } else if (flat.length > expected) {
      flat.removeRange(expected, flat.length);
    }
    return List.generate(rle.height, (y) {
      return List.generate(rle.width, (x) => flat[y * rle.width + x]);
    });
  }

  static bool _valueAt(List<List<bool>> mask, int x, int y) {
    return y < mask.length && x < mask[y].length && mask[y][x];
  }
}

class BinaryMaskExportResult {
  const BinaryMaskExportResult({
    required this.maskJsonPath,
    required this.imagePath,
  });

  final String maskJsonPath;
  final String imagePath;
}

class BinaryMaskExportService {
  const BinaryMaskExportService();

  Future<BinaryMaskExportResult> export({
    required CrackDetectionResult detection,
    required String sourceImagePath,
    required String imageName,
    required Directory outputDirectory,
    required double threshold,
    required int maxWindows,
  }) async {
    final mask = detection.binaryMask;
    if (mask == null || mask.isEmpty) {
      throw StateError('binaryMask is required before export');
    }
    if (!outputDirectory.existsSync()) {
      await outputDirectory.create(recursive: true);
    }

    final safeName = _safeFileStem(imageName);
    final imageExtension = _extension(imageName);
    final imageCopyName = '${safeName}_image$imageExtension';
    final maskJsonName = '${safeName}_binary_mask.json';
    final imageCopyPath = [
      outputDirectory.path,
      imageCopyName,
    ].join(Platform.pathSeparator);
    final maskJsonPath = [
      outputDirectory.path,
      maskJsonName,
    ].join(Platform.pathSeparator);
    final sourceImage = File(sourceImagePath);
    await sourceImage.copy(imageCopyPath);

    final payload = {
      'schemaVersion': 1,
      'source': 'app_offline_onnx',
      'imageName': imageName,
      'width': detection.originalWidth,
      'height': detection.originalHeight,
      'modelVersion': detection.modelVersion,
      'threshold': threshold,
      'maxWindows': maxWindows,
      'crackRatio': detection.crackRatio,
      'binaryMaskRle': BinaryMaskRleCodec.encode(mask).toJson(),
    };
    await File(maskJsonPath).writeAsString(
      jsonEncode(payload),
      flush: true,
    );
    return BinaryMaskExportResult(
      maskJsonPath: maskJsonPath,
      imagePath: imageCopyPath,
    );
  }

  String _safeFileStem(String fileName) {
    final name = _baseName(fileName);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final safe = stem.replaceAll(RegExp('[^A-Za-z0-9_.-]+'), '_');
    return safe.isEmpty ? 'image' : safe;
  }

  String _extension(String fileName) {
    final name = _baseName(fileName);
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '.jpg';
    }
    final extension = name
        .substring(dot)
        .replaceAll(
          RegExp('[^A-Za-z0-9.]'),
          '',
        );
    return extension.isEmpty ? '.jpg' : extension;
  }

  String _baseName(String fileName) {
    return fileName.split(r'\').last.split('/').last;
  }
}
