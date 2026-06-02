/// JCI 检测模块 - 测线分析服务
///
/// 在裂缝掩膜上布置井字形测线（2条横线+2条竖线），
/// 检测测线与裂缝掩膜的交点，并计算三大岩石质量指标。
///
/// 需求: 10.1-10.9
library;

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';

/// 测线分析服务
///
/// 提供井字形测线分析功能，包括：
/// - 布置井字形测线（2横+2竖）
/// - 检测测线与裂缝掩膜的交点
/// - 计算每条测线的有效长度和节理间距
/// - 计算三大指标（裂隙条数/面积、平均节理间距、节理密度）
///
/// 错误处理：
/// - 裂缝掩膜为空（全黑）: 返回空的测线结果，三大指标均为 0
/// - 某条测线无交点: 标记该测线为无效，排除出平均值计算
/// - 像素比例未设置或为 0: 使用默认值 1.0
class ScanlineAnalyzerService {
  /// 创建测线分析服务
  const ScanlineAnalyzerService();

  /// 交点标签前缀列表（A-Z）
  static const _labels = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  /// 分析裂缝掩膜
  ///
  /// [crackMask] 二值化裂缝掩膜（true=裂缝像素）
  /// [pixelRatio] 像素比例（cm/像素），为 0 时使用默认值 1.0
  /// [imageWidth] 图像宽度（像素）
  /// [imageHeight] 图像高度（像素）
  /// [cracks] 已识别的裂缝列表
  ///
  /// 返回 [ScanlineAnalysisResult]，包含各测线结果和三大指标。
  ///
  /// 需求: 10.1-10.9
  ScanlineAnalysisResult analyze({
    required List<List<bool>> crackMask,
    required double pixelRatio,
    required int imageWidth,
    required int imageHeight,
    required List<CrackInfo> cracks,
  }) {
    // 像素比例为 0 时使用默认值 1.0
    final effectivePixelRatio = pixelRatio == 0 ? 1.0 : pixelRatio;

    // 需求 10.1: 布置井字形测线
    final scanlines = layoutScanlines(imageWidth, imageHeight);

    // 处理空掩膜
    if (crackMask.isEmpty || (crackMask.isNotEmpty && crackMask[0].isEmpty)) {
      return _buildEmptyResult(
        scanlines: scanlines,
        pixelRatio: effectivePixelRatio,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        cracks: cracks,
      );
    }

    // 需求 10.2: 计算每条测线与裂缝掩膜的交点
    final scanlineResults = <ScanlineResult>[];

    for (final scanline in scanlines) {
      final intersections = findIntersections(
        scanline,
        crackMask,
        effectivePixelRatio,
      );

      final intersectionCount = intersections.length;
      final isValid = intersectionCount > 0;

      // 需求 10.3: 计算有效长度（第一个交点到最后一个交点的距离）
      double effectiveLength;
      // 需求 10.4: 计算节理间距（有效长度除以交点数）
      double jointSpacing;

      if (isValid) {
        effectiveLength =
            intersections.last.distanceFromStart -
            intersections.first.distanceFromStart;
        jointSpacing = intersectionCount > 0
            ? effectiveLength / intersectionCount
            : 0;
      } else {
        // 需求 10.9: 无交点的测线标记为无效
        effectiveLength = 0;
        jointSpacing = 0;
      }

      scanlineResults.add(
        ScanlineResult(
          name: scanline.name,
          jointSpacing: jointSpacing,
          effectiveLength: effectiveLength,
          intersectionCount: intersectionCount,
          intersections: intersections,
          isValid: isValid,
        ),
      );
    }

    // 计算三大指标
    final indicators = _calculateIndicators(
      scanlineResults: scanlineResults,
      pixelRatio: effectivePixelRatio,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      cracks: cracks,
    );

    return ScanlineAnalysisResult(
      scanlines: scanlineResults,
      indicators: indicators,
    );
  }

  /// 布置井字形测线（2横+2竖）
  ///
  /// 横线位于图像高度的 1/3 和 2/3 处，
  /// 竖线位于图像宽度的 1/3 和 2/3 处。
  ///
  /// [width] 图像宽度（像素）
  /// [height] 图像高度（像素）
  ///
  /// 返回 4 条测线的列表。
  ///
  /// 需求: 10.1
  List<Scanline> layoutScanlines(int width, int height) {
    final h1 = height ~/ 3; // 1/3 高度
    final h2 = (height * 2) ~/ 3; // 2/3 高度
    final v1 = width ~/ 3; // 1/3 宽度
    final v2 = (width * 2) ~/ 3; // 2/3 宽度

    return [
      // 横线1: 在 1/3 高度处，从左到右
      Scanline(
        name: '横线1',
        isHorizontal: true,
        position: h1,
        start: 0,
        end: width - 1,
      ),
      // 横线2: 在 2/3 高度处，从左到右
      Scanline(
        name: '横线2',
        isHorizontal: true,
        position: h2,
        start: 0,
        end: width - 1,
      ),
      // 竖线1: 在 1/3 宽度处，从上到下
      Scanline(
        name: '竖线1',
        isHorizontal: false,
        position: v1,
        start: 0,
        end: height - 1,
      ),
      // 竖线2: 在 2/3 宽度处，从上到下
      Scanline(
        name: '竖线2',
        isHorizontal: false,
        position: v2,
        start: 0,
        end: height - 1,
      ),
    ];
  }

  /// 计算测线与掩膜的交点
  ///
  /// 对于横线，沿 X 轴从 start 到 end 遍历，检测裂缝像素段。
  /// 对于竖线，沿 Y 轴从 start 到 end 遍历，检测裂缝像素段。
  /// 每段连续裂缝像素的中点记为一个交点。
  ///
  /// [scanline] 测线定义
  /// [mask] 二值化裂缝掩膜
  /// [pixelRatio] 像素比例（cm/像素）
  ///
  /// 返回交点列表，按距离起点的距离排序。
  ///
  /// 需求: 10.2, 10.5
  List<ScanlineIntersection> findIntersections(
    Scanline scanline,
    List<List<bool>> mask,
    double pixelRatio,
  ) {
    final intersections = <ScanlineIntersection>[];
    var labelIndex = 0;

    if (scanline.isHorizontal) {
      // 横线: 固定 Y = position，遍历 X 从 start 到 end
      final y = scanline.position;

      // 确保 Y 在掩膜范围内
      if (y < 0 || y >= mask.length) return intersections;

      final row = mask[y];
      final maxX = scanline.end < row.length ? scanline.end : row.length - 1;

      var inCrack = false;
      var crackStart = 0;

      for (var x = scanline.start; x <= maxX; x++) {
        final isCrack = x < row.length && row[x];

        if (isCrack && !inCrack) {
          // 进入裂缝段
          inCrack = true;
          crackStart = x;
        } else if (!isCrack && inCrack) {
          // 离开裂缝段，记录中点
          final midX = (crackStart + x - 1) ~/ 2;
          final pixelDistance = midX - scanline.start;
          // 需求 10.5: 像素距离转换为实际物理距离（cm）
          final distanceCm = pixelDistance * pixelRatio;

          intersections.add(
            ScanlineIntersection(
              label: '交点${_getLabel(labelIndex)}',
              pixelX: midX,
              pixelY: y,
              distanceFromStart: distanceCm,
            ),
          );
          labelIndex++;
          inCrack = false;
        }
      }

      // 处理测线末端仍在裂缝中的情况
      if (inCrack) {
        final midX = (crackStart + maxX) ~/ 2;
        final pixelDistance = midX - scanline.start;
        final distanceCm = pixelDistance * pixelRatio;

        intersections.add(
          ScanlineIntersection(
            label: '交点${_getLabel(labelIndex)}',
            pixelX: midX,
            pixelY: y,
            distanceFromStart: distanceCm,
          ),
        );
      }
    } else {
      // 竖线: 固定 X = position，遍历 Y 从 start 到 end
      final x = scanline.position;

      // 确保 X 在掩膜范围内
      if (mask.isEmpty || x < 0 || x >= mask[0].length) {
        return intersections;
      }

      final maxY = scanline.end < mask.length ? scanline.end : mask.length - 1;

      var inCrack = false;
      var crackStart = 0;

      for (var y = scanline.start; y <= maxY; y++) {
        final isCrack = y < mask.length && x < mask[y].length && mask[y][x];

        if (isCrack && !inCrack) {
          // 进入裂缝段
          inCrack = true;
          crackStart = y;
        } else if (!isCrack && inCrack) {
          // 离开裂缝段，记录中点
          final midY = (crackStart + y - 1) ~/ 2;
          final pixelDistance = midY - scanline.start;
          // 需求 10.5: 像素距离转换为实际物理距离（cm）
          final distanceCm = pixelDistance * pixelRatio;

          intersections.add(
            ScanlineIntersection(
              label: '交点${_getLabel(labelIndex)}',
              pixelX: x,
              pixelY: midY,
              distanceFromStart: distanceCm,
            ),
          );
          labelIndex++;
          inCrack = false;
        }
      }

      // 处理测线末端仍在裂缝中的情况
      if (inCrack) {
        final midY = (crackStart + maxY) ~/ 2;
        final pixelDistance = midY - scanline.start;
        final distanceCm = pixelDistance * pixelRatio;

        intersections.add(
          ScanlineIntersection(
            label: '交点${_getLabel(labelIndex)}',
            pixelX: x,
            pixelY: midY,
            distanceFromStart: distanceCm,
          ),
        );
      }
    }

    return intersections;
  }

  /// 获取交点标签字符
  String _getLabel(int index) {
    if (index < _labels.length) {
      return _labels[index];
    }
    // 超过 Z 后使用数字
    return '${index + 1}';
  }

  /// 计算三大指标
  ///
  /// 需求: 10.6, 10.7, 10.8, 10.9
  ThreeIndicators _calculateIndicators({
    required List<ScanlineResult> scanlineResults,
    required double pixelRatio,
    required int imageWidth,
    required int imageHeight,
    required List<CrackInfo> cracks,
  }) {
    // 计算图像实际面积（m²）
    // 宽度和高度先转为 cm，再转为 m
    final imageWidthCm = imageWidth * pixelRatio;
    final imageHeightCm = imageHeight * pixelRatio;
    final imageAreaM2 = (imageWidthCm / 100) * (imageHeightCm / 100);

    // 需求 10.6: 指标1 = 长度≥25cm的裂隙条数 / 图像实际面积（m²）
    final cracksAbove25cm = cracks.where((c) => c.lengthCm >= 25).length;
    final totalCracks = cracks.length;
    final indicator1 = imageAreaM2 > 0 ? cracksAbove25cm / imageAreaM2 : 0.0;

    // 需求 10.7: 指标2 = 各有效测线节理间距的平均值（cm）
    // 需求 10.9: 无交点的测线排除出平均值计算
    final validScanlines = scanlineResults.where((s) => s.isValid).toList();
    final indicator2 = validScanlines.isNotEmpty
        ? validScanlines.fold<double>(
                0,
                (sum, s) => sum + s.jointSpacing,
              ) /
              validScanlines.length
        : 0.0;

    // 需求 10.8: 指标3 = 裂隙总长度（m）/ 图像实际面积（m²）
    final totalCrackLengthCm = cracks.fold<double>(
      0,
      (sum, c) => sum + c.lengthCm,
    );
    final totalCrackLengthM = totalCrackLengthCm / 100;
    final indicator3 = imageAreaM2 > 0 ? totalCrackLengthM / imageAreaM2 : 0.0;

    return ThreeIndicators(
      indicator1: indicator1,
      indicator2: indicator2,
      indicator3: indicator3,
      totalCracks: totalCracks,
      cracksAbove25cm: cracksAbove25cm,
      totalCrackLength: totalCrackLengthCm,
      imageAreaM2: imageAreaM2,
    );
  }

  /// 构建空结果（掩膜为空时使用）
  ScanlineAnalysisResult _buildEmptyResult({
    required List<Scanline> scanlines,
    required double pixelRatio,
    required int imageWidth,
    required int imageHeight,
    required List<CrackInfo> cracks,
  }) {
    final emptyResults = scanlines
        .map(
          (s) => ScanlineResult(
            name: s.name,
            jointSpacing: 0,
            effectiveLength: 0,
            intersectionCount: 0,
            intersections: const [],
            isValid: false,
          ),
        )
        .toList();

    final indicators = _calculateIndicators(
      scanlineResults: emptyResults,
      pixelRatio: pixelRatio,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      cracks: cracks,
    );

    return ScanlineAnalysisResult(
      scanlines: emptyResults,
      indicators: indicators,
    );
  }
}
