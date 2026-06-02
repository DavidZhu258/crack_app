import 'dart:io';
import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/report_data.dart';
import 'package:crack_app/jci_detection/models/scanline_models.dart';
import 'package:crack_app/jci_detection/services/report_generator_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to create a minimal valid ReportData for testing.
ReportData createTestReportData({
  String imagePath = '../data/TUT/crack_res/res_img/1.jpg',
  int imageWidth = 2048,
  int imageHeight = 1047,
  double pixelRatio = 0.2392,
  double rulerLengthCm = 50.0,
  List<ScanlineResult>? scanlines,
  ThreeIndicators? indicators,
  List<CrackInfo>? cracks,
  double totalLengthCm = 1688.76,
  double averageLengthCm = 18.16,
  int inferenceTimeMs = 17760,
  DateTime? timestamp,
  EngineeringInfo? engineeringInfo,
  ExtractedParameters? extractedParams,
  JciCalculationResult? jciResult,
  RockClassificationResult? classification,
  SupportPlan? supportPlan,
  ManualReview? manualReview,
}) {
  final defaultScanlines =
      scanlines ??
      [
        const ScanlineResult(
          name: '横线1',
          jointSpacing: 62.5,
          effectiveLength: 375.1,
          intersectionCount: 6,
          intersections: [
            ScanlineIntersection(
              label: '交点A',
              pixelX: 432,
              pixelY: 349,
              distanceFromStart: 103.3,
            ),
            ScanlineIntersection(
              label: '交点B',
              pixelX: 622,
              pixelY: 349,
              distanceFromStart: 148.8,
            ),
          ],
          isValid: true,
        ),
        const ScanlineResult(
          name: '横线2',
          jointSpacing: 80.5,
          effectiveLength: 402.4,
          intersectionCount: 5,
          intersections: [
            ScanlineIntersection(
              label: '交点A',
              pixelX: 362,
              pixelY: 698,
              distanceFromStart: 86.6,
            ),
          ],
          isValid: true,
        ),
      ];

  final defaultIndicators =
      indicators ??
      const ThreeIndicators(
        indicator1: 1.3852,
        indicator2: 64.73,
        indicator3: 1.3761,
        totalCracks: 93,
        cracksAbove25cm: 17,
        totalCrackLength: 1688.8,
        imageAreaM2: 12.2722,
      );

  final defaultCracks =
      cracks ??
      [
        const CrackInfo(
          id: 1,
          lengthCm: 66.03,
          lengthPixels: 276,
          x: 520,
          y: 804,
          w: 122,
          h: 219,
        ),
        const CrackInfo(
          id: 2,
          lengthCm: 60.53,
          lengthPixels: 253,
          x: 1292,
          y: 261,
          w: 48,
          h: 229,
        ),
      ];

  return ReportData(
    imagePath: imagePath,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    pixelRatio: pixelRatio,
    rulerLengthCm: rulerLengthCm,
    scanlineResult: ScanlineAnalysisResult(
      scanlines: defaultScanlines,
      indicators: defaultIndicators,
    ),
    crackResult: CrackIdentificationResult(
      cracks: defaultCracks,
      totalLengthCm: totalLengthCm,
      averageLengthCm: averageLengthCm,
    ),
    inferenceTimeMs: inferenceTimeMs,
    timestamp: timestamp ?? DateTime(2025, 11, 5, 17, 12, 57),
    engineeringInfo: engineeringInfo,
    extractedParams: extractedParams,
    jciResult: jciResult,
    classification: classification,
    supportPlan: supportPlan,
    manualReview: manualReview,
  );
}

void main() {
  late ReportGeneratorService service;

  setUp(() {
    service = ReportGeneratorService();
  });

  group('ReportGeneratorService', () {
    group('generateReport', () {
      test('报告应包含报告标题', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('金川矿区岩性自适应支护决策系统检测报告'));
        expect(report, contains('掌子面 JCI 分析与裂缝长度测量报告'));
        expect(report, isNot(contains('掌子面 JCI 检测报告')));
      });

      test('报告前部应包含 App 展示的 JCI、等级、支护和提取参数摘要', () {
        final data = createTestReportData(
          engineeringInfo: const EngineeringInfo(
            rockType: RockType.serpentineMarble,
            depth: 598,
            waterCondition: WaterCondition.damp,
            location: '二矿598',
            projectName: '水泵房',
            inspector: '张三',
            hasSeepage: true,
          ),
          extractedParams: ExtractedParameters(
            rqd: 82.5,
            jointSpacing: 64.73,
            jointDensity: 1.3761,
            resultImage1: Uint8List(0),
            resultImage2: Uint8List(0),
          ),
          jciResult: const JciCalculationResult(
            jciValue: 31.26,
            rmr: 52.4,
            r2: 8,
            r3: 10,
            qValue: 6.2,
            gQ: 57.92,
            hS: 18.4,
            rqdValue: 75,
            jn: 6,
            srf: 2.5,
            componentScores: {'indicator1': 1.3852, 'UCS': 80},
          ),
          classification: const RockClassificationResult(
            originalGrade: RockGrade.ii1,
            finalGrade: RockGrade.ii2,
            wasDowngraded: true,
            downgradeReason: '因渗水降级',
          ),
          supportPlan: const SupportPlan(
            grade: RockGrade.ii2,
            summary: '系统推荐支护方案',
            methods: [
              SupportMethod(
                name: '锚杆',
                parameters: {'长度': '2.5m', '间排距': '1.0m'},
              ),
            ],
          ),
          manualReview: ManualReview.rejected(
            manualGrade: RockGrade.iv,
            selectedSupportPlan: const SupportPlan(
              grade: RockGrade.iv,
              summary: '人工选择 IV 类支护方案',
              methods: [
                SupportMethod(
                  name: 'U36 钢拱架',
                  parameters: {'间距': '0.75m'},
                ),
              ],
            ),
            reviewerName: '张三',
            note: '现场破碎带明显',
          ),
        );

        final report = service.generateReport(data);
        final summaryIdx = report.indexOf('检测结果摘要');
        final imageInfoIdx = report.indexOf('图片:');

        expect(summaryIdx, isNonNegative);
        expect(summaryIdx, lessThan(imageInfoIdx));
        expect(report, contains('工程名称: 水泵房'));
        expect(report, contains('工程地点: 二矿598'));
        expect(report, contains('施工人员: 张三'));
        expect(report, contains('JCI 值: 31.26'));
        expect(report, contains('最终围岩等级: II-2 - 一般'));
        expect(report, contains('人工采用等级: IV - 差'));
        expect(report, contains('支护方案建议: 人工选择 IV 类支护方案'));
        expect(report, contains('U36 钢拱架'));
        expect(report, contains('RQD: 82.50'));
        expect(report, contains('平均节理间距: 64.73 cm'));
        expect(report, contains('节理密度: 1.38 m/m²'));
      });

      test('报告应包含图片路径 (需求 11.2)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains(data.imagePath));
      });

      test('报告应包含图片尺寸 (需求 11.2)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('2048 x 1047 像素'));
      });

      test('报告应包含像素比例 (需求 11.2)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('0.2392 cm'));
      });

      test('报告应包含尺子实际长度', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('50.0 cm'));
      });

      test('报告应包含三大指标汇总 (需求 11.3)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('指标1: 1.3852 条/m²'));
        expect(report, contains('指标2: 平均节理间距: 64.73 cm'));
        expect(report, contains('指标3: 节理密度1.3761 m/m²'));
      });

      test('报告应包含测线统计表 (需求 11.4)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('各测线节理间距统计:'));
        expect(report, contains('横线1'));
        expect(report, contains('横线2'));
        expect(report, contains('62.5'));
        expect(report, contains('375.1'));
      });

      test('报告应包含测线交点详情 (需求 11.5)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('各测线详细交点信息:'));
        expect(report, contains('交点A'));
        expect(report, contains('交点B'));
        expect(report, contains('103.3cm'));
      });

      test('报告应包含裂缝列表 (需求 11.6)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('检测到 2 条裂缝:'));
        expect(report, contains('66.03'));
        expect(report, contains('60.53'));
        expect(report, contains('(520, 804, 122, 219)'));
      });

      test('报告应包含裂缝总长度和平均长度', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('总长度: 1688.76 cm'));
        expect(report, contains('平均长度: 18.16 cm'));
      });

      test('报告应包含推理时间 (需求 11.7)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('推理时间: 17.76s'));
      });

      test('报告应包含时间戳', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('2025-11-05_17-12-57'));
      });

      test('报告应包含分隔线', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('=' * 60));
        expect(report, contains('-' * 68));
      });

      test('报告应包含图像实际尺寸信息', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('图像实际尺寸:'));
        expect(report, contains('裂隙总数: 93 条'));
        expect(report, contains('长度≥25cm的裂隙: 17 条'));
      });

      test('报告应包含计算方法说明', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        expect(report, contains('计算方法:'));
        expect(report, contains('测线布局: 2条横线 + 2条竖线 (井字形)'));
      });

      test('空裂缝列表应正确生成报告', () {
        final data = createTestReportData(
          cracks: [],
          totalLengthCm: 0,
          averageLengthCm: 0,
        );
        final report = service.generateReport(data);

        expect(report, contains('检测到 0 条裂缝:'));
        expect(report, contains('总长度: 0.00 cm'));
        expect(report, contains('平均长度: 0.00 cm'));
      });

      test('空测线列表应正确生成报告', () {
        final data = createTestReportData(
          scanlines: [],
          indicators: const ThreeIndicators(
            indicator1: 0,
            indicator2: 0,
            indicator3: 0,
            totalCracks: 0,
            cracksAbove25cm: 0,
            totalCrackLength: 0,
            imageAreaM2: 0,
          ),
        );
        final report = service.generateReport(data);

        expect(report, contains('各测线节理间距统计:'));
        expect(report, contains('三大指标汇总:'));
      });

      test('报告各段落应按正确顺序排列 (需求 11.9)', () {
        final data = createTestReportData();
        final report = service.generateReport(data);

        final headerIdx = report.indexOf('金川矿区岩性自适应支护决策系统检测报告');
        final imageInfoIdx = report.indexOf('图片:');
        final indicatorsIdx = report.indexOf('岩石质量分析 (三大指标)');
        final scanlineTableIdx = report.indexOf('各测线节理间距统计:');
        final summaryIdx = report.indexOf('三大指标汇总:');
        final detailsIdx = report.indexOf('各测线详细交点信息:');
        final crackListIdx = report.indexOf('检测到');
        final inferenceIdx = report.indexOf('推理时间:');

        expect(headerIdx, lessThan(imageInfoIdx));
        expect(imageInfoIdx, lessThan(indicatorsIdx));
        expect(indicatorsIdx, lessThan(scanlineTableIdx));
        expect(scanlineTableIdx, lessThan(summaryIdx));
        expect(summaryIdx, lessThan(detailsIdx));
        expect(detailsIdx, lessThan(crackListIdx));
        expect(crackListIdx, lessThan(inferenceIdx));
      });
    });

    group('saveReport', () {
      late Directory tempDir;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync('report_test_');
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      test('应将报告保存为 .txt 文件 (需求 11.8)', () async {
        const content = '测试报告内容';
        final path = await service.saveReport(
          content: content,
          outputDir: tempDir.path,
          fileName: 'test_report.txt',
        );

        final file = File(path);
        expect(file.existsSync(), isTrue);
        expect(path.endsWith('.txt'), isTrue);
      });

      test('保存的文件内容应与原内容一致', () async {
        const content = '这是一份完整的测试报告\n包含多行内容\n第三行';
        final path = await service.saveReport(
          content: content,
          outputDir: tempDir.path,
          fileName: 'test_report.txt',
        );

        final savedContent = File(path).readAsStringSync();
        expect(savedContent, equals(content));
      });

      test('输出目录不存在时应自动创建', () async {
        final nestedDir = '${tempDir.path}/nested/deep/dir';
        const content = '测试内容';

        final path = await service.saveReport(
          content: content,
          outputDir: nestedDir,
          fileName: 'report.txt',
        );

        expect(File(path).existsSync(), isTrue);
      });

      test('返回的路径应包含文件名', () async {
        const content = '测试';
        final path = await service.saveReport(
          content: content,
          outputDir: tempDir.path,
          fileName: '1_report.txt',
        );

        expect(path, contains('1_report.txt'));
      });

      test('生成的报告保存后再读取应一致 (往返一致性)', () async {
        final data = createTestReportData();
        final reportContent = service.generateReport(data);

        final path = await service.saveReport(
          content: reportContent,
          outputDir: tempDir.path,
          fileName: 'roundtrip_report.txt',
        );

        final savedContent = File(path).readAsStringSync();
        expect(savedContent, equals(reportContent));
      });
    });
  });
}
