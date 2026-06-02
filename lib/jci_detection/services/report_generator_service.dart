/// JCI 检测模块 - 报告生成服务
///
/// 将检测结果汇总为结构化文本报告，按照固定格式模板生成。
/// 报告包含图片信息、三大指标、测线统计、交点详情、裂缝列表和推理时间。
///
/// 需求: 11.1-11.9
/// - 11.1: 生成结构化文本报告文件
/// - 11.2: 报告中包含图片信息（路径、尺寸、像素比例）
/// - 11.3: 报告中包含三大指标汇总
/// - 11.4: 报告中包含各测线节理间距统计表
/// - 11.5: 报告中包含各测线详细交点信息
/// - 11.6: 报告中包含裂缝详细列表
/// - 11.7: 报告中包含推理时间
/// - 11.8: 将报告保存为 .txt 文件到本地存储
/// - 11.9: 使用固定格式模板生成报告
library;

// The report template is intentionally written as sequential append calls so
// each section reads in the same order as the generated document.
// ignore_for_file: cascade_invocations

import 'dart:io';

import 'package:crack_app/core/app_branding.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/report_data.dart';
import 'package:intl/intl.dart';

/// 报告生成服务
///
/// 根据 ReportData 生成结构化文本报告，格式与 1_report.txt 模板一致。
class ReportGeneratorService {
  /// 分隔线常量
  static final String _separator = '=' * 60;
  static final String _dashSeparator = '-' * 68;
  static final String _crackDashSeparator = '-' * 60;

  /// 生成检测报告
  ///
  /// [data] 完整检测结果（含测线分析和裂缝列表）
  /// 返回报告文本内容
  ///
  /// 需求: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6, 11.7, 11.9
  String generateReport(ReportData data) {
    final buffer = StringBuffer();

    _writeHeader(buffer);
    _writeResultSummary(buffer, data);
    _writeImageInfo(buffer, data);
    _writeThreeIndicators(buffer, data);
    _writeScanlineTable(buffer, data);
    _writeThreeIndicatorsSummary(buffer, data);
    _writeScanlineDetails(buffer, data);
    _writeCrackList(buffer, data);
    _writeInferenceTime(buffer, data);

    return buffer.toString();
  }

  /// 保存报告到文件
  ///
  /// [content] 报告文本内容
  /// [outputDir] 输出目录
  /// [fileName] 文件名（如"1_report.txt"）
  /// 返回保存的文件完整路径
  ///
  /// 需求: 11.8
  Future<String> saveReport({
    required String content,
    required String outputDir,
    required String fileName,
  }) async {
    final directory = Directory(outputDir);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsString(content);

    return filePath;
  }

  // ============ 私有方法：各报告段落生成 ============

  /// 写入报告头部
  void _writeHeader(StringBuffer buffer) {
    buffer.writeln(_separator);
    buffer.writeln(appDetectionReportTitle);
    buffer.writeln('掌子面 JCI 分析与裂缝长度测量报告');
    buffer.writeln(_separator);
    buffer.writeln();
  }

  void _writeResultSummary(StringBuffer buffer, ReportData data) {
    final hasSummary =
        data.engineeringInfo != null ||
        data.extractedParams != null ||
        data.jciResult != null ||
        data.classification != null ||
        data.supportPlan != null ||
        data.manualReview != null;
    if (!hasSummary) {
      return;
    }

    buffer.writeln('检测结果摘要');
    buffer.writeln(_separator);

    final engineering = data.engineeringInfo;
    if (engineering != null) {
      if (engineering.projectName.isNotEmpty) {
        buffer.writeln('工程名称: ${engineering.projectName}');
      }
      if (engineering.projectLocation.isNotEmpty) {
        buffer.writeln('工程地点: ${engineering.projectLocation}');
      }
      if (engineering.workerName.isNotEmpty) {
        buffer.writeln('施工人员: ${engineering.workerName}');
      }
      buffer.writeln('岩性: ${engineering.rockType.displayName}');
      buffer.writeln(
        '工程所在中段标高: ${_formatDouble(engineering.elevation, 2)} m',
      );
      buffer.writeln('地下水状况: ${engineering.waterCondition.displayName}');
      buffer.writeln('是否渗水: ${engineering.hasSeepage ? '是' : '否'}');
      buffer.writeln('是否均质混合岩: ${engineering.isHomogeneous ? '是' : '否'}');
      buffer.writeln();
    }

    final extracted = data.extractedParams;
    if (extracted != null) {
      buffer.writeln('提取参数:');
      buffer.writeln('  RQD: ${_formatDouble(extracted.rqd, 2)}');
      buffer.writeln(
        '  平均节理间距: ${_formatDouble(extracted.jointSpacing, 2)} cm',
      );
      buffer.writeln(
        '  节理密度: ${_formatDouble(extracted.jointDensity, 2)} m/m²',
      );
      buffer.writeln();
    }

    final jci = data.jciResult;
    if (jci != null) {
      buffer.writeln('JCI 计算结果:');
      buffer.writeln('  JCI 值: ${_formatDouble(jci.jciValue, 2)}');
      buffer.writeln('  RMR: ${_formatDouble(jci.rmr, 2)}');
      buffer.writeln('  R2: ${jci.r2}');
      buffer.writeln('  R3: ${jci.r3}');
      buffer.writeln('  Q: ${_formatDouble(jci.qValue, 4)}');
      buffer.writeln('  g(Q): ${_formatDouble(jci.gQ, 2)}');
      buffer.writeln('  h(S): ${_formatDouble(jci.hS, 2)}');
      buffer.writeln('  RQD_value: ${_formatDouble(jci.rqdValue, 2)}');
      buffer.writeln('  Jn: ${_formatDouble(jci.jn, 2)}');
      buffer.writeln('  SRF: ${_formatDouble(jci.srf, 2)}');
      if (jci.componentScores.isNotEmpty) {
        buffer.writeln('  计算输入/分项:');
        for (final entry in jci.componentScores.entries) {
          buffer.writeln('    ${entry.key}: ${_formatDouble(entry.value, 4)}');
        }
      }
      buffer.writeln();
    }

    final classification = data.classification;
    if (classification != null) {
      buffer.writeln('围岩等级:');
      buffer.writeln('  原始围岩等级: ${classification.originalGrade.fullName}');
      buffer.writeln('  最终围岩等级: ${classification.finalGrade.fullName}');
      if (classification.wasDowngraded) {
        buffer.writeln(
          '  降级说明: ${classification.downgradeReason ?? '因现场条件降级'}',
        );
      }
      buffer.writeln();
    }

    final effectiveSupportPlan = data.manualReview?.effectiveSupportPlan(
      data.supportPlan ??
          const SupportPlan(
            grade: RockGrade.v,
            methods: [],
            summary: '暂无支护方案',
            isPlaceholder: true,
          ),
    );
    final supportPlan = effectiveSupportPlan ?? data.supportPlan;
    if (supportPlan != null) {
      buffer.writeln('支护方案建议: ${supportPlan.summary}');
      for (final method in supportPlan.methods) {
        buffer.writeln('  - ${method.name}');
        for (final param in method.parameters.entries) {
          buffer.writeln('      ${param.key}: ${param.value}');
        }
      }
      buffer.writeln();
    }

    final review = data.manualReview;
    if (review != null) {
      buffer.writeln('人工复核:');
      buffer.writeln(
        '  复核结论: ${review.acceptedRecognitionResult ? '接受识别结果' : '人工调整'}',
      );
      if (review.hasOverride) {
        buffer.writeln('  人工采用等级: ${review.manualGrade?.fullName ?? ''}');
        buffer.writeln(
          '  人工支护方案: ${review.selectedSupportPlan?.summary ?? ''}',
        );
      }
      if (review.reviewerName.isNotEmpty) {
        buffer.writeln('  复核人员: ${review.reviewerName}');
      }
      if (review.note.isNotEmpty) {
        buffer.writeln('  复核说明: ${review.note}');
      }
      final reviewedAt = DateFormat(
        'yyyy-MM-dd HH:mm:ss',
      ).format(review.reviewedAt);
      buffer.writeln('  复核时间: $reviewedAt');
      buffer.writeln();
    }

    buffer.writeln(_separator);
    buffer.writeln();
  }

  /// 写入图片信息段
  ///
  /// 需求 11.2: 报告中包含图片信息（路径、尺寸、像素比例）
  void _writeImageInfo(StringBuffer buffer, ReportData data) {
    final timeStr = DateFormat('yyyy-MM-dd_HH-mm-ss').format(data.timestamp);

    buffer.writeln('图片: ${data.imagePath}');
    buffer.writeln('时间: $timeStr');
    buffer.writeln(
      '图片尺寸: ${data.imageWidth} x ${data.imageHeight} 像素',
    );
    buffer.writeln();
    buffer.writeln('尺子信息:');
    buffer.writeln(
      '  实际长度: ${_formatDouble(data.rulerLengthCm, 1)} cm',
    );
    buffer.writeln(
      '  像素比例: 1 像素 = ${_formatDouble(data.pixelRatio, 4)} cm',
    );
    buffer.writeln();
  }

  /// 写入三大指标段头部和图像实际尺寸
  ///
  /// 需求 11.3: 报告中包含三大指标汇总
  void _writeThreeIndicators(StringBuffer buffer, ReportData data) {
    final indicators = data.scanlineResult.indicators;
    final widthCm = data.imageWidth * data.pixelRatio;
    final heightCm = data.imageHeight * data.pixelRatio;
    final areaCm2 = widthCm * heightCm;
    final totalCrackLengthM = indicators.totalCrackLength / 100;

    buffer.writeln(_separator);
    buffer.writeln('岩石质量分析 (三大指标)');
    buffer.writeln(_separator);
    buffer.writeln();
    buffer.writeln('图像实际尺寸:');
    buffer.writeln('  宽度: ${_formatDouble(widthCm, 1)} cm');
    buffer.writeln('  高度: ${_formatDouble(heightCm, 1)} cm');
    buffer.writeln(
      '  面积: ${_formatDouble(areaCm2, 1)} cm²'
      ' (${_formatDouble(indicators.imageAreaM2, 4)} m²)',
    );
    buffer.writeln('  裂隙总数: ${indicators.totalCracks} 条');
    buffer.writeln('  长度≥25cm的裂隙: ${indicators.cracksAbove25cm} 条');
    buffer.writeln(
      '  裂隙总长度: ${_formatDouble(indicators.totalCrackLength, 1)} cm'
      ' (${_formatDouble(totalCrackLengthM, 2)} m)',
    );
    buffer.writeln();
    buffer.writeln('计算方法:');
    buffer.writeln('  指标1: (长度≥25cm的裂隙条数) / 图像实际面积（m²）');
    buffer.writeln(
      '  指标2 - 节理间距: (第一个交点到最后一个交点的距离) / 交点个数',
    );
    buffer.writeln('  指标3: 裂隙总长度（m） / 图像实际面积（m²）');
    buffer.writeln('  测线布局: 2条横线 + 2条竖线 (井字形)');
    buffer.writeln();
  }

  /// 写入测线统计表
  ///
  /// 需求 11.4: 报告中包含各测线节理间距统计表
  void _writeScanlineTable(StringBuffer buffer, ReportData data) {
    buffer.writeln('各测线节理间距统计:');
    buffer.writeln(_dashSeparator);
    buffer.writeln(
      '${'测线'.padRight(9)}'
      '${'节理间距(cm)'.padRight(20)}'
      '${'有效长度(cm)'.padRight(20)}'
      '交点数       ',
    );
    buffer.writeln(_dashSeparator);

    for (final scanline in data.scanlineResult.scanlines) {
      buffer.writeln(
        '${scanline.name.padRight(9)}'
        '${_formatDouble(scanline.jointSpacing, 1).padRight(16)}'
        '${_formatDouble(scanline.effectiveLength, 1).padRight(20)}'
        '${scanline.intersectionCount.toString().padRight(10)}',
      );
    }

    buffer.writeln(_dashSeparator);
    buffer.writeln();
  }

  /// 写入三大指标汇总
  void _writeThreeIndicatorsSummary(StringBuffer buffer, ReportData data) {
    final indicators = data.scanlineResult.indicators;

    buffer.writeln('三大指标汇总:');
    buffer.writeln(_separator);
    buffer.writeln(
      '  指标1: ${_formatDouble(indicators.indicator1, 4)} 条/m²',
    );
    buffer.writeln(
      '  指标2: 平均节理间距: ${_formatDouble(indicators.indicator2, 2)} cm',
    );
    buffer.writeln(
      '  指标3: 节理密度${_formatDouble(indicators.indicator3, 4)} m/m²',
    );
    buffer.writeln(_separator);
    buffer.writeln();
    buffer.writeln('注: 有效长度 = 第一个交点到最后一个交点的距离');
    buffer.writeln();
  }

  /// 写入各测线详细交点信息
  ///
  /// 需求 11.5: 报告中包含各测线详细交点信息
  void _writeScanlineDetails(StringBuffer buffer, ReportData data) {
    buffer.writeln('各测线详细交点信息:');
    buffer.writeln();

    for (final scanline in data.scanlineResult.scanlines) {
      buffer.writeln(
        '${scanline.name} '
        '(有效长度: ${_formatDouble(scanline.effectiveLength, 1)}cm, '
        '交点数: ${scanline.intersectionCount}):',
      );

      for (final intersection in scanline.intersections) {
        buffer.writeln(
          '  ${intersection.label}: '
          '位置(${intersection.pixelX}.0, ${intersection.pixelY}.0), '
          '距离起点: '
          '${_formatDouble(intersection.distanceFromStart, 1)}cm',
        );
      }

      buffer.writeln();
    }

    buffer.writeln(_separator);
    buffer.writeln();
  }

  /// 写入裂缝列表
  ///
  /// 需求 11.6: 报告中包含裂缝详细列表
  void _writeCrackList(StringBuffer buffer, ReportData data) {
    final cracks = data.crackResult.cracks;

    buffer.writeln('检测到 ${cracks.length} 条裂缝:');
    buffer.writeln(_crackDashSeparator);
    buffer.writeln(
      '${'ID'.padRight(6)}'
      '${'长度(cm)'.padRight(15)}'
      '${'长度(像素)'.padRight(17)}'
      '位置(x,y,w,h)',
    );
    buffer.writeln(_crackDashSeparator);

    for (final crack in cracks) {
      buffer.writeln(
        '${crack.id.toString().padRight(6)}'
        '${_formatDouble(crack.lengthCm, 2).padRight(13)}'
        '${crack.lengthPixels.toDouble().toString().padRight(17)}'
        '(${crack.x}, ${crack.y}, ${crack.w}, ${crack.h})',
      );
    }

    buffer.writeln(_crackDashSeparator);
    buffer.writeln(
      '总长度: ${_formatDouble(data.crackResult.totalLengthCm, 2)} cm',
    );
    buffer.writeln(
      '平均长度: ${_formatDouble(data.crackResult.averageLengthCm, 2)} cm',
    );
    buffer.writeln();
  }

  /// 写入推理时间
  ///
  /// 需求 11.7: 报告中包含推理时间
  void _writeInferenceTime(StringBuffer buffer, ReportData data) {
    final seconds = data.inferenceTimeMs / 1000;
    buffer.writeln('推理时间: ${_formatDouble(seconds, 2)}s');
    buffer.writeln();
  }

  /// 格式化浮点数为指定小数位数的字符串
  String _formatDouble(double value, int decimalPlaces) {
    return value.toStringAsFixed(decimalPlaces);
  }
}
