import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:crack_app/jci_detection/services/jci_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// 模拟的 PathProvider 实现，用于测试
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  MockPathProviderPlatform(this.testDir);
  final String testDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => testDir;
}

void main() {
  late Directory tempDir;
  late JciStorageService storageService;

  /// 创建测试用的 JciDetectionResult
  JciDetectionResult createTestResult({
    String? id,
    DateTime? timestamp,
  }) {
    final testImageData = Uint8List.fromList([1, 2, 3, 4, 5]);

    return JciDetectionResult(
      id: id ?? 'test-id-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: timestamp ?? DateTime.now(),
      image1Path: '/path/to/image1.jpg',
      image2Path: '/path/to/image2.jpg',
      resultImage1: testImageData,
      resultImage2: testImageData,
      extractedParams: ExtractedParameters(
        rqd: 75.5,
        jointSpacing: 0.5,
        jointDensity: 2,
        resultImage1: testImageData,
        resultImage2: testImageData,
      ),
      engineeringInfo: const EngineeringInfo(
        rockType: RockType.granite,
        depth: 100,
        waterCondition: WaterCondition.dry,
        location: '测试地点',
        projectName: '测试工程',
        inspector: '测试人员',
        isHomogeneous: true,
      ),
      jciResult: const JciCalculationResult(
        jciValue: 35.5,
        componentScores: {
          'RQD得分': 22.65,
          '节理间距得分': 5.0,
          '岩石类型得分': 4.0,
          '埋深得分': 2.25,
          '地下水得分': 2.0,
        },
      ),
      classification: const RockClassificationResult(
        originalGrade: RockGrade.i2,
        finalGrade: RockGrade.i2,
      ),
      supportPlan: const SupportPlan(
        grade: RockGrade.i2,
        methods: [
          SupportMethod(
            name: '锚杆',
            parameters: {'长度': '2.5m', '间距': '1.5m'},
          ),
        ],
        summary: '测试支护方案',
      ),
    );
  }

  setUp(() async {
    // 创建临时目录用于测试
    tempDir = await Directory.systemTemp.createTemp('jci_storage_test_');

    // 设置模拟的 PathProvider
    PathProviderPlatform.instance = MockPathProviderPlatform(tempDir.path);

    storageService = JciStorageService();
  });

  tearDown(() async {
    // 清理临时目录
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JciStorageService', () {
    group('saveResult', () {
      test('应该成功保存检测结果到文件', () async {
        final result = createTestResult(id: 'save-test-1');

        await storageService.saveResult(result);

        // 验证文件已创建
        final file = File('${tempDir.path}/jci_results/${result.id}.json');
        expect(file.existsSync(), isTrue);

        // 验证文件内容是有效的 JSON
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        expect(json['id'], equals(result.id));
      });

      test('应该覆盖已存在的同 ID 结果', () async {
        final result1 = createTestResult(id: 'overwrite-test');
        final result2 = JciDetectionResult(
          id: 'overwrite-test',
          timestamp: DateTime.now(),
          image1Path: '/new/path/image1.jpg',
          image2Path: '/new/path/image2.jpg',
          resultImage1: Uint8List.fromList([10, 20, 30]),
          resultImage2: Uint8List.fromList([10, 20, 30]),
          extractedParams: ExtractedParameters(
            rqd: 80,
            jointSpacing: 0.6,
            jointDensity: 2.5,
            resultImage1: Uint8List.fromList([10, 20, 30]),
            resultImage2: Uint8List.fromList([10, 20, 30]),
          ),
          engineeringInfo: const EngineeringInfo(
            rockType: RockType.mediumThickMarble,
            depth: 150,
            waterCondition: WaterCondition.damp,
          ),
          jciResult: const JciCalculationResult(
            jciValue: 40,
            componentScores: {'RQD得分': 24.0},
          ),
          classification: const RockClassificationResult(
            originalGrade: RockGrade.i1,
            finalGrade: RockGrade.i1,
          ),
          supportPlan: const SupportPlan(
            grade: RockGrade.i1,
            methods: [],
            summary: '新方案',
          ),
        );

        await storageService.saveResult(result1);
        await storageService.saveResult(result2);

        final retrieved = await storageService.getResult('overwrite-test');
        expect(retrieved?.image1Path, equals('/new/path/image1.jpg'));
      });

      test('应该保存并读取同步元数据', () async {
        final result = createTestResult(id: 'sync-metadata').copyWith(
          syncStatus: SyncStatus.pendingUpload,
          remoteRecordId: 'remote-1',
          syncError: 'waiting',
          operatorUserId: 'user-1',
          inferenceMode: 'auto',
          modelVersion: 'savss_256',
          updatedAt: DateTime.utc(2026, 5, 4, 12, 30),
        );

        await storageService.saveResult(result);

        final retrieved = await storageService.getResult('sync-metadata');

        expect(retrieved, isNotNull);
        expect(retrieved!.syncStatus, equals(SyncStatus.pendingUpload));
        expect(retrieved.remoteRecordId, equals('remote-1'));
        expect(retrieved.syncError, equals('waiting'));
        expect(retrieved.operatorUserId, equals('user-1'));
        expect(retrieved.inferenceMode, equals('auto'));
        expect(retrieved.modelVersion, equals('savss_256'));
        expect(
          retrieved.updatedAt?.toIso8601String(),
          equals('2026-05-04T12:30:00.000Z'),
        );
      });

      test('应该保存并读取人工复核信息', () async {
        const manualSupportPlan = SupportPlan(
          grade: RockGrade.iv,
          methods: [
            SupportMethod(
              name: '人工选择支护',
              parameters: {'支护等级': 'IV'},
            ),
          ],
          summary: '人工选择 IV 类支护方案',
        );
        final result = createTestResult(id: 'manual-review').copyWith(
          manualReview: ManualReview(
            acceptedRecognitionResult: false,
            manualGrade: RockGrade.iv,
            selectedSupportPlan: manualSupportPlan,
            reviewerName: '王工',
            note: '现场节理发育程度高于图像识别结果',
            reviewedAt: DateTime.utc(2026, 5, 7, 9, 30),
          ),
          syncStatus: SyncStatus.pendingUpload,
        );

        await storageService.saveResult(result);

        final retrieved = await storageService.getResult('manual-review');

        expect(retrieved, isNotNull);
        expect(retrieved!.manualReview, isNotNull);
        expect(
          retrieved.manualReview!.acceptedRecognitionResult,
          isFalse,
        );
        expect(retrieved.manualReview!.manualGrade, equals(RockGrade.iv));
        expect(
          retrieved.manualReview!.selectedSupportPlan?.grade,
          equals(RockGrade.iv),
        );
        expect(retrieved.manualReview!.reviewerName, equals('王工'));
        expect(retrieved.manualReview!.note, contains('现场节理'));
        expect(retrieved.effectiveGrade, equals(RockGrade.iv));
        expect(retrieved.effectiveSupportPlan.grade, equals(RockGrade.iv));
      });
    });

    group('getResult', () {
      test('应该成功读取已保存的结果', () async {
        final original = createTestResult(id: 'get-test-1');
        await storageService.saveResult(original);

        final retrieved = await storageService.getResult('get-test-1');

        expect(retrieved, isNotNull);
        expect(retrieved!.id, equals(original.id));
        expect(retrieved.image1Path, equals(original.image1Path));
        expect(retrieved.engineeringInfo.rockType, equals(RockType.granite));
        expect(retrieved.jciResult.jciValue, equals(35.5));
        expect(retrieved.classification.finalGrade, equals(RockGrade.i2));
      });

      test('应该返回 null 当结果不存在时', () async {
        final result = await storageService.getResult('non-existent-id');
        expect(result, isNull);
      });

      test('应该返回 null 当文件损坏时', () async {
        // 创建一个损坏的 JSON 文件
        final storageDir = Directory('${tempDir.path}/jci_results');
        await storageDir.create(recursive: true);
        final file = File('${storageDir.path}/corrupted.json');
        await file.writeAsString('{ invalid json }');

        final result = await storageService.getResult('corrupted');
        expect(result, isNull);
      });
    });

    group('getAllResults', () {
      test('应该返回空列表当没有保存的结果时', () async {
        final results = await storageService.getAllResults();
        expect(results, isEmpty);
      });

      test('应该返回所有保存的结果', () async {
        final result1 = createTestResult(id: 'all-test-1');
        final result2 = createTestResult(id: 'all-test-2');
        final result3 = createTestResult(id: 'all-test-3');

        await storageService.saveResult(result1);
        await storageService.saveResult(result2);
        await storageService.saveResult(result3);

        final results = await storageService.getAllResults();
        expect(results.length, equals(3));
      });

      test('应该按时间倒序排列结果', () async {
        final now = DateTime.now();
        final result1 = createTestResult(
          id: 'order-test-1',
          timestamp: now.subtract(const Duration(hours: 2)),
        );
        final result2 = createTestResult(
          id: 'order-test-2',
          timestamp: now.subtract(const Duration(hours: 1)),
        );
        final result3 = createTestResult(
          id: 'order-test-3',
          timestamp: now,
        );

        // 故意以非时间顺序保存
        await storageService.saveResult(result2);
        await storageService.saveResult(result1);
        await storageService.saveResult(result3);

        final results = await storageService.getAllResults();

        expect(results[0].id, equals('order-test-3')); // 最新
        expect(results[1].id, equals('order-test-2'));
        expect(results[2].id, equals('order-test-1')); // 最旧
      });

      test('应该跳过损坏的文件并返回有效结果', () async {
        final validResult = createTestResult(id: 'valid-result');
        await storageService.saveResult(validResult);

        // 创建一个损坏的文件
        final storageDir = Directory('${tempDir.path}/jci_results');
        final corruptedFile = File('${storageDir.path}/corrupted.json');
        await corruptedFile.writeAsString('{ invalid json }');

        final results = await storageService.getAllResults();
        expect(results.length, equals(1));
        expect(results[0].id, equals('valid-result'));
      });
    });

    group('deleteResult', () {
      test('应该成功删除已存在的结果', () async {
        final result = createTestResult(id: 'delete-test-1');
        await storageService.saveResult(result);

        // 验证文件存在
        var retrieved = await storageService.getResult('delete-test-1');
        expect(retrieved, isNotNull);

        // 删除
        await storageService.deleteResult('delete-test-1');

        // 验证文件已删除
        retrieved = await storageService.getResult('delete-test-1');
        expect(retrieved, isNull);
      });

      test('应该静默处理删除不存在的结果', () async {
        // 不应抛出异常
        await expectLater(
          storageService.deleteResult('non-existent-id'),
          completes,
        );
      });
    });

    group('JSON 序列化往返测试', () {
      test('Property 7: 保存后读取应返回等价数据', () async {
        final original = createTestResult(id: 'roundtrip-test');
        await storageService.saveResult(original);

        final retrieved = await storageService.getResult('roundtrip-test');

        expect(retrieved, isNotNull);

        // 验证所有字段
        expect(retrieved!.id, equals(original.id));
        expect(
          retrieved.timestamp.toIso8601String(),
          equals(original.timestamp.toIso8601String()),
        );
        expect(retrieved.image1Path, equals(original.image1Path));
        expect(retrieved.image2Path, equals(original.image2Path));
        expect(retrieved.resultImage1, equals(original.resultImage1));
        expect(retrieved.resultImage2, equals(original.resultImage2));

        // ExtractedParameters
        expect(
          retrieved.extractedParams.rqd,
          equals(original.extractedParams.rqd),
        );
        expect(
          retrieved.extractedParams.jointSpacing,
          equals(original.extractedParams.jointSpacing),
        );
        expect(
          retrieved.extractedParams.jointDensity,
          equals(original.extractedParams.jointDensity),
        );

        // EngineeringInfo
        expect(
          retrieved.engineeringInfo.rockType,
          equals(original.engineeringInfo.rockType),
        );
        expect(
          retrieved.engineeringInfo.depth,
          equals(original.engineeringInfo.depth),
        );
        expect(
          retrieved.engineeringInfo.waterCondition,
          equals(original.engineeringInfo.waterCondition),
        );
        expect(
          retrieved.engineeringInfo.location,
          equals(original.engineeringInfo.location),
        );
        expect(
          retrieved.engineeringInfo.projectLocation,
          equals(original.engineeringInfo.projectLocation),
        );
        expect(
          retrieved.engineeringInfo.projectName,
          equals(original.engineeringInfo.projectName),
        );
        expect(
          retrieved.engineeringInfo.inspector,
          equals(original.engineeringInfo.inspector),
        );
        expect(
          retrieved.engineeringInfo.workerName,
          equals(original.engineeringInfo.workerName),
        );
        expect(
          retrieved.engineeringInfo.elevation,
          equals(original.engineeringInfo.elevation),
        );
        expect(
          retrieved.engineeringInfo.isHomogeneous,
          equals(original.engineeringInfo.isHomogeneous),
        );
        expect(
          retrieved.engineeringInfo.hasSeepage,
          equals(original.engineeringInfo.hasSeepage),
        );

        // JciCalculationResult
        expect(
          retrieved.jciResult.jciValue,
          equals(original.jciResult.jciValue),
        );
        expect(
          retrieved.jciResult.componentScores,
          equals(original.jciResult.componentScores),
        );

        // RockClassificationResult
        expect(
          retrieved.classification.originalGrade,
          equals(original.classification.originalGrade),
        );
        expect(
          retrieved.classification.finalGrade,
          equals(original.classification.finalGrade),
        );
        expect(
          retrieved.classification.wasDowngraded,
          equals(original.classification.wasDowngraded),
        );
        expect(
          retrieved.classification.downgradeReason,
          equals(original.classification.downgradeReason),
        );

        // SupportPlan
        expect(
          retrieved.supportPlan.grade,
          equals(original.supportPlan.grade),
        );
        expect(
          retrieved.supportPlan.summary,
          equals(original.supportPlan.summary),
        );
        expect(
          retrieved.supportPlan.isPlaceholder,
          equals(original.supportPlan.isPlaceholder),
        );
        expect(
          retrieved.supportPlan.methods.length,
          equals(original.supportPlan.methods.length),
        );
        expect(
          retrieved.supportPlan.methods[0].name,
          equals(original.supportPlan.methods[0].name),
        );
        expect(
          retrieved.supportPlan.methods[0].parameters,
          equals(original.supportPlan.methods[0].parameters),
        );
      });

      test('应该正确处理所有 RockType 枚举值', () async {
        for (final rockType in RockType.values) {
          final result = JciDetectionResult(
            id: 'rocktype-${rockType.name}',
            timestamp: DateTime.now(),
            image1Path: '/path/image1.jpg',
            image2Path: '/path/image2.jpg',
            resultImage1: Uint8List.fromList([1, 2, 3]),
            resultImage2: Uint8List.fromList([1, 2, 3]),
            extractedParams: ExtractedParameters(
              rqd: 50,
              jointSpacing: 0.5,
              jointDensity: 2,
              resultImage1: Uint8List.fromList([1, 2, 3]),
              resultImage2: Uint8List.fromList([1, 2, 3]),
            ),
            engineeringInfo: EngineeringInfo(
              rockType: rockType,
              depth: 100,
              waterCondition: WaterCondition.dry,
            ),
            jciResult: const JciCalculationResult(
              jciValue: 30,
              componentScores: {},
            ),
            classification: const RockClassificationResult(
              originalGrade: RockGrade.ii1,
              finalGrade: RockGrade.ii1,
            ),
            supportPlan: const SupportPlan(
              grade: RockGrade.ii1,
              methods: [],
              summary: '',
            ),
          );

          await storageService.saveResult(result);
          final retrieved = await storageService.getResult(
            'rocktype-${rockType.name}',
          );

          expect(retrieved?.engineeringInfo.rockType, equals(rockType));
        }
      });

      test('应该正确处理所有 WaterCondition 枚举值', () async {
        for (final waterCondition in WaterCondition.values) {
          final result = JciDetectionResult(
            id: 'water-${waterCondition.name}',
            timestamp: DateTime.now(),
            image1Path: '/path/image1.jpg',
            image2Path: '/path/image2.jpg',
            resultImage1: Uint8List.fromList([1, 2, 3]),
            resultImage2: Uint8List.fromList([1, 2, 3]),
            extractedParams: ExtractedParameters(
              rqd: 50,
              jointSpacing: 0.5,
              jointDensity: 2,
              resultImage1: Uint8List.fromList([1, 2, 3]),
              resultImage2: Uint8List.fromList([1, 2, 3]),
            ),
            engineeringInfo: EngineeringInfo(
              rockType: RockType.granite,
              depth: 100,
              waterCondition: waterCondition,
            ),
            jciResult: const JciCalculationResult(
              jciValue: 30,
              componentScores: {},
            ),
            classification: const RockClassificationResult(
              originalGrade: RockGrade.ii1,
              finalGrade: RockGrade.ii1,
            ),
            supportPlan: const SupportPlan(
              grade: RockGrade.ii1,
              methods: [],
              summary: '',
            ),
          );

          await storageService.saveResult(result);
          final retrieved = await storageService.getResult(
            'water-${waterCondition.name}',
          );

          expect(
            retrieved?.engineeringInfo.waterCondition,
            equals(waterCondition),
          );
        }
      });

      test('应该正确处理所有 RockGrade 枚举值', () async {
        for (final grade in RockGrade.values) {
          final result = JciDetectionResult(
            id: 'grade-${grade.name}',
            timestamp: DateTime.now(),
            image1Path: '/path/image1.jpg',
            image2Path: '/path/image2.jpg',
            resultImage1: Uint8List.fromList([1, 2, 3]),
            resultImage2: Uint8List.fromList([1, 2, 3]),
            extractedParams: ExtractedParameters(
              rqd: 50,
              jointSpacing: 0.5,
              jointDensity: 2,
              resultImage1: Uint8List.fromList([1, 2, 3]),
              resultImage2: Uint8List.fromList([1, 2, 3]),
            ),
            engineeringInfo: const EngineeringInfo(
              rockType: RockType.granite,
              depth: 100,
              waterCondition: WaterCondition.dry,
            ),
            jciResult: const JciCalculationResult(
              jciValue: 30,
              componentScores: {},
            ),
            classification: RockClassificationResult(
              originalGrade: grade,
              finalGrade: grade,
            ),
            supportPlan: SupportPlan(
              grade: grade,
              methods: const [],
              summary: '',
            ),
          );

          await storageService.saveResult(result);
          final retrieved = await storageService.getResult(
            'grade-${grade.name}',
          );

          expect(retrieved?.classification.originalGrade, equals(grade));
          expect(retrieved?.classification.finalGrade, equals(grade));
          expect(retrieved?.supportPlan.grade, equals(grade));
        }
      });
    });

    group(
      'Property 9: 检测结果存储往返一致性',
      () {
        // Feature: jci-calculation, Property 9: 检测结果存储往返一致性
        // **Validates: Requirements 8.2, 8.3**
        //
        // 对于任意有效的 JciDetectionResult 对象，保存到本地存储后再读取，
        // 应得到与原对象等价的数据（除时间戳等元数据外）。

        /// 生成随机字节数组
        Uint8List randomBytes(Random rng, {int maxLen = 50}) {
          final len = rng.nextInt(maxLen) + 1;
          return Uint8List.fromList(
            List.generate(len, (_) => rng.nextInt(256)),
          );
        }

        /// 生成随机 ASCII 字符串
        String randomString(Random rng, {int maxLen = 20}) {
          final len = rng.nextInt(maxLen) + 1;
          return String.fromCharCodes(
            List.generate(len, (_) => rng.nextInt(26) + 97),
          );
        }

        /// 生成随机正 double
        double randomPositiveDouble(Random rng, {double max = 1000}) {
          return rng.nextDouble() * max + 0.01;
        }

        /// 随机选择枚举值
        T randomEnum<T>(Random rng, List<T> values) {
          return values[rng.nextInt(values.length)];
        }

        /// 生成随机 SupportMethod
        SupportMethod randomSupportMethod(Random rng) {
          final paramCount = rng.nextInt(3) + 1;
          final params = <String, String>{};
          for (var j = 0; j < paramCount; j++) {
            params[randomString(rng, maxLen: 8)] = randomString(
              rng,
              maxLen: 10,
            );
          }
          return SupportMethod(
            name: randomString(rng, maxLen: 10),
            parameters: params,
          );
        }

        /// 生成随机 JciDetectionResult
        JciDetectionResult randomResult(Random rng, int index) {
          final rockType = randomEnum(rng, RockType.values);
          final waterCondition = randomEnum(rng, WaterCondition.values);
          final originalGrade = randomEnum(rng, RockGrade.values);
          final finalGrade = randomEnum(rng, RockGrade.values);
          final supportGrade = randomEnum(rng, RockGrade.values);
          final wasDowngraded = rng.nextBool();
          final hasSeepage = rng.nextBool();
          final isHomogeneous = rng.nextBool();
          final isPlaceholder = rng.nextBool();

          final methodCount = rng.nextInt(4);
          final methods = List.generate(
            methodCount,
            (_) => randomSupportMethod(rng),
          );

          final scoreCount = rng.nextInt(5) + 1;
          final scores = <String, double>{};
          for (var j = 0; j < scoreCount; j++) {
            scores[randomString(rng, maxLen: 8)] = rng.nextDouble() * 100;
          }

          final imageData1 = randomBytes(rng);
          final imageData2 = randomBytes(rng);
          final resultImg1 = randomBytes(rng);
          final resultImg2 = randomBytes(rng);

          return JciDetectionResult(
            id: 'pbt-$index',
            timestamp: DateTime(
              2020 + rng.nextInt(5),
              rng.nextInt(12) + 1,
              rng.nextInt(28) + 1,
              rng.nextInt(24),
              rng.nextInt(60),
              rng.nextInt(60),
            ),
            image1Path: '/path/${randomString(rng)}.jpg',
            image2Path: '/path/${randomString(rng)}.jpg',
            resultImage1: resultImg1,
            resultImage2: resultImg2,
            extractedParams: ExtractedParameters(
              rqd: rng.nextDouble() * 100,
              jointSpacing: randomPositiveDouble(rng, max: 10),
              jointDensity: randomPositiveDouble(rng, max: 50),
              resultImage1: imageData1,
              resultImage2: imageData2,
            ),
            engineeringInfo: EngineeringInfo(
              rockType: rockType,
              depth: randomPositiveDouble(rng, max: 2000),
              waterCondition: waterCondition,
              location: randomString(rng, maxLen: 15),
              projectName: randomString(rng, maxLen: 15),
              inspector: randomString(rng, maxLen: 10),
              isHomogeneous: isHomogeneous,
              hasSeepage: hasSeepage,
            ),
            jciResult: JciCalculationResult(
              jciValue: rng.nextDouble() * 100 - 20,
              componentScores: scores,
            ),
            classification: RockClassificationResult(
              originalGrade: originalGrade,
              finalGrade: finalGrade,
              wasDowngraded: wasDowngraded,
              downgradeReason: wasDowngraded ? randomString(rng) : null,
            ),
            supportPlan: SupportPlan(
              grade: supportGrade,
              methods: methods,
              summary: randomString(rng, maxLen: 30),
              isPlaceholder: isPlaceholder,
            ),
          );
        }

        /// 验证两个 JciDetectionResult 对象在序列化往返后等价
        void verifyRoundTrip(
          JciDetectionResult original,
          JciDetectionResult retrieved,
        ) {
          expect(retrieved.id, equals(original.id));
          expect(
            retrieved.timestamp.toIso8601String(),
            equals(original.timestamp.toIso8601String()),
          );
          expect(retrieved.image1Path, equals(original.image1Path));
          expect(retrieved.image2Path, equals(original.image2Path));
          expect(retrieved.resultImage1, equals(original.resultImage1));
          expect(retrieved.resultImage2, equals(original.resultImage2));

          // ExtractedParameters
          expect(
            retrieved.extractedParams.rqd,
            equals(original.extractedParams.rqd),
          );
          expect(
            retrieved.extractedParams.jointSpacing,
            equals(original.extractedParams.jointSpacing),
          );
          expect(
            retrieved.extractedParams.jointDensity,
            equals(original.extractedParams.jointDensity),
          );
          expect(
            retrieved.extractedParams.resultImage1,
            equals(original.extractedParams.resultImage1),
          );
          expect(
            retrieved.extractedParams.resultImage2,
            equals(original.extractedParams.resultImage2),
          );

          // EngineeringInfo
          expect(
            retrieved.engineeringInfo.rockType,
            equals(original.engineeringInfo.rockType),
          );
          expect(
            retrieved.engineeringInfo.depth,
            equals(original.engineeringInfo.depth),
          );
          expect(
            retrieved.engineeringInfo.waterCondition,
            equals(original.engineeringInfo.waterCondition),
          );
          expect(
            retrieved.engineeringInfo.location,
            equals(original.engineeringInfo.location),
          );
          expect(
            retrieved.engineeringInfo.projectName,
            equals(original.engineeringInfo.projectName),
          );
          expect(
            retrieved.engineeringInfo.inspector,
            equals(original.engineeringInfo.inspector),
          );
          expect(
            retrieved.engineeringInfo.isHomogeneous,
            equals(original.engineeringInfo.isHomogeneous),
          );
          expect(
            retrieved.engineeringInfo.hasSeepage,
            equals(original.engineeringInfo.hasSeepage),
          );

          // JciCalculationResult
          expect(
            retrieved.jciResult.jciValue,
            equals(original.jciResult.jciValue),
          );
          expect(
            retrieved.jciResult.componentScores,
            equals(original.jciResult.componentScores),
          );

          // RockClassificationResult
          expect(
            retrieved.classification.originalGrade,
            equals(original.classification.originalGrade),
          );
          expect(
            retrieved.classification.finalGrade,
            equals(original.classification.finalGrade),
          );
          expect(
            retrieved.classification.wasDowngraded,
            equals(original.classification.wasDowngraded),
          );
          expect(
            retrieved.classification.downgradeReason,
            equals(original.classification.downgradeReason),
          );

          // SupportPlan
          expect(
            retrieved.supportPlan.grade,
            equals(original.supportPlan.grade),
          );
          expect(
            retrieved.supportPlan.summary,
            equals(original.supportPlan.summary),
          );
          expect(
            retrieved.supportPlan.isPlaceholder,
            equals(original.supportPlan.isPlaceholder),
          );
          expect(
            retrieved.supportPlan.methods.length,
            equals(original.supportPlan.methods.length),
          );
          for (var m = 0; m < original.supportPlan.methods.length; m++) {
            expect(
              retrieved.supportPlan.methods[m].name,
              equals(original.supportPlan.methods[m].name),
            );
            expect(
              retrieved.supportPlan.methods[m].parameters,
              equals(original.supportPlan.methods[m].parameters),
            );
          }
        }

        test(
          '属性测试: 随机 JciDetectionResult 存储往返一致性 (100 次迭代)',
          () async {
            final rng = Random(42); // 固定种子保证可重现

            for (var i = 0; i < 100; i++) {
              final original = randomResult(rng, i);

              await storageService.saveResult(original);
              final retrieved = await storageService.getResult(original.id);

              expect(
                retrieved,
                isNotNull,
                reason: '迭代 $i: 保存后应能读取结果 (id=${original.id})',
              );

              verifyRoundTrip(original, retrieved!);
            }
          },
        );
      },
    );
  });
}
