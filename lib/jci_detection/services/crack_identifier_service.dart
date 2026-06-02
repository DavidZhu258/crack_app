/// JCI 检测模块 - 裂缝独立识别服务
///
/// 从裂缝掩膜中识别每条独立裂缝并测量其长度和位置。
/// 使用连通域分析（BFS flood-fill）标记独立裂缝区域，
/// 使用轮廓周长/2近似计算裂缝长度。
///
/// 需求: 12.1-12.6
library;

import 'dart:collection';
import 'dart:math';

import 'package:crack_app/jci_detection/models/crack_info.dart';

/// 裂缝独立识别服务
///
/// 提供从二值化裂缝掩膜中识别独立裂缝的功能，包括：
/// - 连通域分析（标记每个独立裂缝区域）
/// - 裂缝长度测量（使用轮廓周长/2近似）
/// - 边界框计算
/// - 按长度降序排序输出
/// - 总长度和平均长度计算
///
/// 错误处理：
/// - 掩膜中无裂缝（全黑）: 返回空裂缝列表，总长度和平均长度为 0
/// - 连通域过多（>500）: 仅保留最大的 500 个连通域
class CrackIdentifierService {
  /// 创建裂缝识别服务
  const CrackIdentifierService();

  /// 连通域数量上限
  static const int maxComponents = 500;

  /// 从裂缝掩膜中识别独立裂缝
  ///
  /// [crackMask] 二值化裂缝掩膜（true=裂缝像素）
  /// [pixelRatio] 像素比例（cm/像素）
  ///
  /// 返回 [CrackIdentificationResult]，包含按长度降序排列的裂缝列表、
  /// 总长度和平均长度。
  ///
  /// 需求: 12.1-12.6
  CrackIdentificationResult identifyCracks({
    required List<List<bool>> crackMask,
    required double pixelRatio,
  }) {
    // 需求 12.1: 通过连通域分析识别出每条独立裂缝
    final labelMap = labelConnectedComponents(crackMask);

    final height = crackMask.length;
    if (height == 0) {
      return const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 0,
        averageLengthCm: 0,
      );
    }
    final width = crackMask[0].length;
    if (width == 0) {
      return const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 0,
        averageLengthCm: 0,
      );
    }

    // 收集每个连通域的像素信息和边界框
    final componentData = <int, _ComponentData>{};

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final label = labelMap[y][x];
        if (label > 0) {
          final data = componentData.putIfAbsent(
            label,
            () => _ComponentData(
              minX: x,
              maxX: x,
              minY: y,
              maxY: y,
              pixelCount: 0,
            ),
          );
          data
            ..minX = min(data.minX, x)
            ..maxX = max(data.maxX, x)
            ..minY = min(data.minY, y)
            ..maxY = max(data.maxY, y)
            ..pixelCount = data.pixelCount + 1;
        }
      }
    }

    // 掩膜中无裂缝（全黑）: 返回空裂缝列表
    if (componentData.isEmpty) {
      return const CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 0,
        averageLengthCm: 0,
      );
    }

    // 连通域过多（>500）: 仅保留最大的 500 个连通域
    var componentEntries = componentData.entries.toList();
    if (componentEntries.length > maxComponents) {
      componentEntries.sort(
        (a, b) => b.value.pixelCount.compareTo(
          a.value.pixelCount,
        ),
      );
      componentEntries = componentEntries.sublist(0, maxComponents);
    }

    // 为每个连通域计算裂缝长度和边界框
    final cracks = <CrackInfo>[];
    var crackId = 1;

    for (final entry in componentEntries) {
      final label = entry.key;
      final data = entry.value;

      // 提取该连通域的掩膜
      final componentMask = _extractComponentMask(
        labelMap,
        label,
        data.minX,
        data.minY,
        data.maxX,
        data.maxY,
      );

      // 需求 12.2: 计算每条裂缝的像素长度
      final lengthPixels = measureCrackLength(componentMask);

      // 需求 12.3: 根据 Pixel_Ratio 将像素长度转换为实际长度（cm）
      final lengthCm = lengthPixels * pixelRatio;

      // 需求 12.4: 记录每条裂缝的位置信息（边界框 x, y, w, h）
      cracks.add(
        CrackInfo(
          id: crackId,
          lengthCm: lengthCm,
          lengthPixels: lengthPixels,
          x: data.minX,
          y: data.minY,
          w: data.maxX - data.minX + 1,
          h: data.maxY - data.minY + 1,
        ),
      );
      crackId++;
    }

    // 需求 12.5: 按裂缝长度从大到小排序输出裂缝列表
    cracks.sort((a, b) => b.lengthCm.compareTo(a.lengthCm));

    // 重新分配 ID（按排序后的顺序）
    final sortedCracks = <CrackInfo>[];
    for (var i = 0; i < cracks.length; i++) {
      sortedCracks.add(cracks[i].copyWith(id: i + 1));
    }

    // 需求 12.6: 计算裂缝总长度和平均长度
    final totalLengthCm = sortedCracks.fold<double>(
      0,
      (sum, crack) => sum + crack.lengthCm,
    );
    final averageLengthCm = sortedCracks.isEmpty
        ? 0.0
        : totalLengthCm / sortedCracks.length;

    return CrackIdentificationResult(
      cracks: sortedCracks,
      totalLengthCm: totalLengthCm,
      averageLengthCm: averageLengthCm,
    );
  }

  /// 连通域分析，标记每个独立裂缝区域
  ///
  /// 使用 BFS（广度优先搜索）flood-fill 算法，
  /// 以 4-连通性标记连通域。
  ///
  /// [mask] 二值化裂缝掩膜（true=裂缝像素）
  ///
  /// 返回与输入掩膜同尺寸的标签矩阵，
  /// 0 表示非裂缝像素，正整数表示连通域编号。
  ///
  /// 需求: 12.1
  List<List<int>> labelConnectedComponents(List<List<bool>> mask) {
    final height = mask.length;
    if (height == 0) return [];

    final width = mask[0].length;
    if (width == 0) return [[]];

    // 初始化标签矩阵
    final labels = List.generate(
      height,
      (_) => List.filled(width, 0),
    );

    var currentLabel = 0;

    // 4-连通方向: 上、下、左、右
    const dx = [0, 0, -1, 1];
    const dy = [-1, 1, 0, 0];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // 跳过非裂缝像素和已标记像素
        if (!mask[y][x] || labels[y][x] != 0) continue;

        // BFS flood-fill
        currentLabel++;
        final queue = Queue<_Point>()..add(_Point(x, y));
        labels[y][x] = currentLabel;

        while (queue.isNotEmpty) {
          final point = queue.removeFirst();

          for (var d = 0; d < 4; d++) {
            final nx = point.x + dx[d];
            final ny = point.y + dy[d];

            if (nx >= 0 &&
                nx < width &&
                ny >= 0 &&
                ny < height &&
                mask[ny][nx] &&
                labels[ny][nx] == 0) {
              labels[ny][nx] = currentLabel;
              queue.add(_Point(nx, ny));
            }
          }
        }
      }
    }

    return labels;
  }

  /// 计算单个裂缝的像素长度（使用轮廓周长/2近似）
  ///
  /// 统计边界像素数量（至少有一个 4-连通邻居为非裂缝像素的裂缝像素），
  /// 然后除以 2 得到近似长度。
  ///
  /// [componentMask] 单个连通域的二值化掩膜（true=裂缝像素）
  ///
  /// 返回近似的像素长度（至少为 1）。
  ///
  /// 需求: 12.2
  int measureCrackLength(List<List<bool>> componentMask) {
    final height = componentMask.length;
    if (height == 0) return 0;

    final width = componentMask[0].length;
    if (width == 0) return 0;

    // 4-连通方向: 上、下、左、右
    const dx = [0, 0, -1, 1];
    const dy = [-1, 1, 0, 0];

    var boundaryPixelCount = 0;
    var totalPixelCount = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (!componentMask[y][x]) continue;

        totalPixelCount++;

        // 检查是否为边界像素
        var isBoundary = false;
        for (var d = 0; d < 4; d++) {
          final nx = x + dx[d];
          final ny = y + dy[d];

          // 超出边界或邻居为非裂缝像素 → 当前像素是边界像素
          if (nx < 0 ||
              nx >= width ||
              ny < 0 ||
              ny >= height ||
              !componentMask[ny][nx]) {
            isBoundary = true;
            break;
          }
        }

        if (isBoundary) {
          boundaryPixelCount++;
        }
      }
    }

    // 无裂缝像素
    if (totalPixelCount == 0) return 0;

    // 轮廓周长/2近似裂缝长度，至少为 1
    final length = (boundaryPixelCount / 2).round();
    return max(1, length);
  }

  /// 从标签矩阵中提取指定连通域的局部掩膜
  List<List<bool>> _extractComponentMask(
    List<List<int>> labelMap,
    int label,
    int minX,
    int minY,
    int maxX,
    int maxY,
  ) {
    final maskHeight = maxY - minY + 1;
    final maskWidth = maxX - minX + 1;

    return List.generate(
      maskHeight,
      (y) => List.generate(
        maskWidth,
        (x) => labelMap[y + minY][x + minX] == label,
      ),
    );
  }
}

/// 连通域数据（内部使用）
class _ComponentData {
  _ComponentData({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.pixelCount,
  });

  int minX;
  int maxX;
  int minY;
  int maxY;
  int pixelCount;
}

/// 二维坐标点（内部使用）
class _Point {
  const _Point(this.x, this.y);

  final int x;
  final int y;
}
