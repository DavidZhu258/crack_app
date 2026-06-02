/// JCI 检测模块 - 本地存储服务
///
/// 提供 JCI 检测结果的本地存储功能，包括保存、读取、删除等操作。
/// 使用 JSON 序列化将数据存储到本地文件系统。
///
/// 需求: 8.1-8.5
/// - 8.1: 检测完成后提供"保存结果"按钮
/// - 8.2: 用户点击保存时将检测结果保存到本地存储
/// - 8.3: 保存内容包括原始图像、检测结果图、提取参数、JCI 值、
///        围岩等级、支护方案、检测时间、地点、人员信息
/// - 8.4: 按时间倒序显示已保存的检测记录
/// - 8.5: 点击历史记录项显示完整的检测详情
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';
import 'package:crack_app/jci_detection/models/sync_models.dart';
import 'package:path_provider/path_provider.dart';

/// JCI 检测结果本地存储服务
///
/// 使用 JSON 文件存储检测结果，每个结果存储为单独的文件。
/// 图像数据以 Base64 编码存储在 JSON 中。
///
/// Property 7: 检测结果存储往返一致性
/// 对于任意有效的 JciDetectionResult 对象，保存到本地存储后再读取，
/// 应得到与原对象等价的数据。
class JciStorageService {
  /// 存储目录名称
  static const String _storageDirName = 'jci_results';

  /// 获取存储目录
  Future<Directory> _getStorageDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final storageDir = Directory('${appDir.path}/$_storageDirName');
    if (!storageDir.existsSync()) {
      await storageDir.create(recursive: true);
    }
    return storageDir;
  }

  /// 获取结果文件路径
  Future<File> _getResultFile(String id) async {
    final storageDir = await _getStorageDirectory();
    return File('${storageDir.path}/$id.json');
  }

  /// 保存检测结果
  ///
  /// [result] 要保存的检测结果
  ///
  /// 将检测结果序列化为 JSON 并保存到本地文件。
  /// 文件名使用结果的 ID。
  ///
  /// 需求: 8.2, 8.3
  Future<void> saveResult(JciDetectionResult result) async {
    final file = await _getResultFile(result.id);
    final json = _resultToJson(result);
    final jsonString = jsonEncode(json);
    await file.writeAsString(jsonString);
  }

  /// 获取所有历史记录
  ///
  /// 返回按时间倒序排列的所有检测结果列表。
  /// 如果某个文件损坏或无法解析，将跳过该文件。
  ///
  /// 需求: 8.4
  Future<List<JciDetectionResult>> getAllResults() async {
    final storageDir = await _getStorageDirectory();
    final results = <JciDetectionResult>[];

    if (!storageDir.existsSync()) {
      return results;
    }

    final files = await storageDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    for (final file in files) {
      try {
        final jsonString = await file.readAsString();
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        final result = _resultFromJson(json);
        results.add(result);
      } on FormatException {
        // JSON 格式错误，跳过损坏的文件
        continue;
      } on FileSystemException {
        // 文件系统错误，跳过该文件
        continue;
      }
    }

    // 按时间倒序排列（需求 8.4）
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  /// 获取单条记录
  ///
  /// [id] 记录的唯一标识符
  ///
  /// 返回指定 ID 的检测结果，如果不存在或无法解析则返回 null。
  ///
  /// 需求: 8.5
  Future<JciDetectionResult?> getResult(String id) async {
    final file = await _getResultFile(id);

    if (!file.existsSync()) {
      return null;
    }

    try {
      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return _resultFromJson(json);
    } on FormatException {
      // JSON 格式错误
      return null;
    } on FileSystemException {
      // 文件系统错误
      return null;
    }
  }

  /// 删除记录
  ///
  /// [id] 要删除的记录的唯一标识符
  ///
  /// 删除指定 ID 的检测结果文件。
  /// 如果文件不存在，不会抛出异常。
  Future<void> deleteResult(String id) async {
    final file = await _getResultFile(id);

    if (file.existsSync()) {
      await file.delete();
    }
  }

  // ============ JSON 序列化方法 ============

  /// 将检测结果转换为可同步 JSON。
  ///
  /// 云端同步客户端复用同一套结构，保证本地保存和云端下载可往返。
  Map<String, dynamic> resultToJson(JciDetectionResult result) {
    return _resultToJson(result);
  }

  /// 从同步 JSON 解析检测结果。
  JciDetectionResult resultFromJson(Map<String, dynamic> json) {
    return _resultFromJson(json);
  }

  /// 将 JciDetectionResult 转换为 JSON Map
  Map<String, dynamic> _resultToJson(JciDetectionResult result) {
    return {
      'id': result.id,
      'timestamp': result.timestamp.toIso8601String(),
      'image1Path': result.image1Path,
      'image2Path': result.image2Path,
      'resultImage1': base64Encode(result.resultImage1),
      'resultImage2': base64Encode(result.resultImage2),
      'extractedParams': _extractedParamsToJson(result.extractedParams),
      'engineeringInfo': _engineeringInfoToJson(result.engineeringInfo),
      'jciResult': _jciResultToJson(result.jciResult),
      'classification': _classificationToJson(result.classification),
      'supportPlan': _supportPlanToJson(result.supportPlan),
      'reportPath': result.reportPath,
      'syncStatus': result.syncStatus.name,
      'remoteRecordId': result.remoteRecordId,
      'syncError': result.syncError,
      'operatorUserId': result.operatorUserId,
      'inferenceMode': result.inferenceMode,
      'modelVersion': result.modelVersion,
      'updatedAt': result.updatedAt?.toIso8601String(),
      'manualReview': result.manualReview == null
          ? null
          : _manualReviewToJson(result.manualReview!),
    };
  }

  /// 从 JSON Map 解析 JciDetectionResult
  JciDetectionResult _resultFromJson(Map<String, dynamic> json) {
    return JciDetectionResult(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      image1Path: json['image1Path'] as String,
      image2Path: json['image2Path'] as String,
      resultImage1: _bytesFromBase64(json['resultImage1'] as String?),
      resultImage2: _bytesFromBase64(json['resultImage2'] as String?),
      extractedParams: _extractedParamsFromJson(
        json['extractedParams'] as Map<String, dynamic>,
      ),
      engineeringInfo: _engineeringInfoFromJson(
        json['engineeringInfo'] as Map<String, dynamic>,
      ),
      jciResult: _jciResultFromJson(
        json['jciResult'] as Map<String, dynamic>,
      ),
      classification: _classificationFromJson(
        json['classification'] as Map<String, dynamic>,
      ),
      supportPlan: _supportPlanFromJson(
        json['supportPlan'] as Map<String, dynamic>,
      ),
      reportPath: json['reportPath'] as String?,
      syncStatus: _syncStatusFromJson(json['syncStatus'] as String?),
      remoteRecordId: json['remoteRecordId'] as String?,
      syncError: json['syncError'] as String?,
      operatorUserId: json['operatorUserId'] as String?,
      inferenceMode: json['inferenceMode'] as String? ?? 'offline',
      modelVersion: json['modelVersion'] as String?,
      updatedAt: (json['updatedAt'] as String?) != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      manualReview: (json['manualReview'] as Map<String, dynamic>?) == null
          ? null
          : _manualReviewFromJson(
              json['manualReview'] as Map<String, dynamic>,
            ),
    );
  }

  SyncStatus _syncStatusFromJson(String? value) {
    if (value == null || value.isEmpty) {
      return SyncStatus.localOnly;
    }
    return SyncStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => SyncStatus.localOnly,
    );
  }

  /// 将 ExtractedParameters 转换为 JSON Map
  Map<String, dynamic> _extractedParamsToJson(ExtractedParameters params) {
    return {
      'rqd': params.rqd,
      'jointSpacing': params.jointSpacing,
      'jointDensity': params.jointDensity,
      'resultImage1': base64Encode(params.resultImage1),
      'resultImage2': base64Encode(params.resultImage2),
    };
  }

  /// 从 JSON Map 解析 ExtractedParameters
  ExtractedParameters _extractedParamsFromJson(Map<String, dynamic> json) {
    return ExtractedParameters(
      rqd: (json['rqd'] as num).toDouble(),
      jointSpacing: (json['jointSpacing'] as num).toDouble(),
      jointDensity: (json['jointDensity'] as num).toDouble(),
      resultImage1: _bytesFromBase64(json['resultImage1'] as String?),
      resultImage2: _bytesFromBase64(json['resultImage2'] as String?),
    );
  }

  Uint8List _bytesFromBase64(String? value) {
    if (value == null || value.isEmpty) {
      return Uint8List(0);
    }
    return base64Decode(value);
  }

  /// 将 EngineeringInfo 转换为 JSON Map
  Map<String, dynamic> _engineeringInfoToJson(EngineeringInfo info) {
    return {
      'rockType': info.rockType.name,
      'depth': info.depth,
      'elevation': info.elevation,
      'waterCondition': info.waterCondition.name,
      'location': info.location,
      'projectLocation': info.projectLocation,
      'projectName': info.projectName,
      'inspector': info.inspector,
      'workerName': info.workerName,
      'isHomogeneous': info.isHomogeneous,
      'hasSeepage': info.hasSeepage,
    };
  }

  /// 从 JSON Map 解析 EngineeringInfo
  EngineeringInfo _engineeringInfoFromJson(Map<String, dynamic> json) {
    return EngineeringInfo(
      rockType: _rockTypeFromName(json['rockType'] as String?),
      depth: ((json['elevation'] ?? json['depth']) as num).toDouble(),
      waterCondition: _waterConditionFromName(
        json['waterCondition'] as String?,
      ),
      location:
          json['projectLocation'] as String? ??
          json['location'] as String? ??
          '',
      projectName: json['projectName'] as String? ?? '',
      inspector:
          json['workerName'] as String? ?? json['inspector'] as String? ?? '',
      isHomogeneous: json['isHomogeneous'] as bool? ?? false,
      hasSeepage: json['hasSeepage'] as bool? ?? false,
    );
  }

  WaterCondition _waterConditionFromName(String? name) {
    return WaterCondition.values.firstWhere(
      (e) => e.name == name,
      orElse: () => WaterCondition.dry,
    );
  }

  /// 将 JciCalculationResult 转换为 JSON Map
  Map<String, dynamic> _jciResultToJson(JciCalculationResult result) {
    return {
      'jciValue': result.jciValue,
      'rmr': result.rmr,
      'r2': result.r2,
      'r3': result.r3,
      'qValue': result.qValue,
      'gQ': result.gQ,
      'hS': result.hS,
      'rqdValue': result.rqdValue,
      'jn': result.jn,
      'srf': result.srf,
      'componentScores': result.componentScores,
    };
  }

  /// 从 JSON Map 解析 JciCalculationResult
  JciCalculationResult _jciResultFromJson(Map<String, dynamic> json) {
    return JciCalculationResult(
      jciValue: (json['jciValue'] as num).toDouble(),
      rmr: (json['rmr'] as num?)?.toDouble() ?? 0,
      r2: (json['r2'] as num?)?.toInt() ?? 0,
      r3: (json['r3'] as num?)?.toInt() ?? 0,
      qValue: (json['qValue'] as num?)?.toDouble() ?? 0,
      gQ: (json['gQ'] as num?)?.toDouble() ?? 0,
      hS: (json['hS'] as num?)?.toDouble() ?? 0,
      rqdValue: (json['rqdValue'] as num?)?.toDouble() ?? 0,
      jn: (json['jn'] as num?)?.toDouble() ?? 0,
      srf: (json['srf'] as num?)?.toDouble() ?? 0,
      componentScores: (json['componentScores'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
    );
  }

  /// 将 RockClassificationResult 转换为 JSON Map
  Map<String, dynamic> _classificationToJson(RockClassificationResult result) {
    return {
      'originalGrade': result.originalGrade.name,
      'finalGrade': result.finalGrade.name,
      'wasDowngraded': result.wasDowngraded,
      'downgradeReason': result.downgradeReason,
    };
  }

  /// 从 JSON Map 解析 RockClassificationResult
  RockClassificationResult _classificationFromJson(Map<String, dynamic> json) {
    return RockClassificationResult(
      originalGrade: _rockGradeFromName(json['originalGrade'] as String?),
      finalGrade: _rockGradeFromName(json['finalGrade'] as String?),
      wasDowngraded: json['wasDowngraded'] as bool? ?? false,
      downgradeReason: json['downgradeReason'] as String?,
    );
  }

  /// 将 SupportPlan 转换为 JSON Map
  Map<String, dynamic> _supportPlanToJson(SupportPlan plan) {
    return {
      'grade': plan.grade.name,
      'methods': plan.methods.map(_supportMethodToJson).toList(),
      'summary': plan.summary,
      'isPlaceholder': plan.isPlaceholder,
    };
  }

  /// 从 JSON Map 解析 SupportPlan
  SupportPlan _supportPlanFromJson(Map<String, dynamic> json) {
    return SupportPlan(
      grade: _rockGradeFromName(json['grade'] as String?),
      methods: (json['methods'] as List<dynamic>)
          .map((e) => _supportMethodFromJson(e as Map<String, dynamic>))
          .toList(),
      summary: json['summary'] as String,
      isPlaceholder: json['isPlaceholder'] as bool? ?? false,
    );
  }

  Map<String, dynamic> _manualReviewToJson(ManualReview review) {
    return {
      'acceptedRecognitionResult': review.acceptedRecognitionResult,
      'manualGrade': review.manualGrade?.name,
      'selectedSupportPlan': review.selectedSupportPlan == null
          ? null
          : _supportPlanToJson(review.selectedSupportPlan!),
      'reviewerName': review.reviewerName,
      'note': review.note,
      'reviewedAt': review.reviewedAt.toIso8601String(),
    };
  }

  ManualReview _manualReviewFromJson(Map<String, dynamic> json) {
    final selectedSupportPlanJson =
        json['selectedSupportPlan'] as Map<String, dynamic>?;
    return ManualReview(
      acceptedRecognitionResult:
          json['acceptedRecognitionResult'] as bool? ?? true,
      manualGrade: _nullableRockGradeFromName(json['manualGrade'] as String?),
      selectedSupportPlan: selectedSupportPlanJson == null
          ? null
          : _supportPlanFromJson(selectedSupportPlanJson),
      reviewerName: json['reviewerName'] as String? ?? '',
      note: json['note'] as String? ?? '',
      reviewedAt: DateTime.parse(json['reviewedAt'] as String),
    );
  }

  RockType _rockTypeFromName(String? name) {
    return switch (name) {
      'serpentineMarble' => RockType.serpentineMarble,
      'mediumThickMarble' => RockType.mediumThickMarble,
      'ultrabasicRock' => RockType.ultrabasicRock,
      'mixedRock' => RockType.mixedRock,
      'granite' => RockType.granite,
      'biotiteGneiss' => RockType.biotiteGneiss,
      // Legacy generic lithology names from earlier builds.
      'limestone' => RockType.mediumThickMarble,
      'sandstone' => RockType.mixedRock,
      'shale' => RockType.mixedRock,
      'mudstone' => RockType.mixedRock,
      'other' => RockType.mixedRock,
      _ => RockType.mediumThickMarble,
    };
  }

  RockGrade _rockGradeFromName(String? name) {
    return switch (name) {
      'I-1' => RockGrade.i1,
      'I-2' => RockGrade.i2,
      'II-1' => RockGrade.ii1,
      'II-2' => RockGrade.ii2,
      'III' => RockGrade.iii,
      'IV' => RockGrade.iv,
      'V' => RockGrade.v,
      'i1' => RockGrade.i1,
      'i2' => RockGrade.i2,
      'ii1' => RockGrade.ii1,
      'ii2' => RockGrade.ii2,
      'iii' => RockGrade.iii,
      'iv' => RockGrade.iv,
      'v' => RockGrade.v,
      // Legacy seven-grade names from earlier builds.
      'iii1' => RockGrade.iii,
      'iii2' => RockGrade.iv,
      'Ⅰ1级' => RockGrade.i1,
      'Ⅰ2级' => RockGrade.i2,
      'Ⅱ1级' => RockGrade.ii1,
      'Ⅱ2级' => RockGrade.ii2,
      'Ⅲ1级' => RockGrade.iii,
      'Ⅲ2级' => RockGrade.iv,
      'Ⅳ级' => RockGrade.v,
      _ => RockGrade.v,
    };
  }

  RockGrade? _nullableRockGradeFromName(String? name) {
    if (name == null || name.isEmpty) {
      return null;
    }
    return _rockGradeFromName(name);
  }

  /// 将 SupportMethod 转换为 JSON Map
  Map<String, dynamic> _supportMethodToJson(SupportMethod method) {
    return {
      'name': method.name,
      'parameters': method.parameters,
    };
  }

  /// 从 JSON Map 解析 SupportMethod
  SupportMethod _supportMethodFromJson(Map<String, dynamic> json) {
    return SupportMethod(
      name: json['name'] as String,
      parameters: (json['parameters'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, value as String),
      ),
    );
  }
}
