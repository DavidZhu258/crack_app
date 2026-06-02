/// 表单验证状态
///
/// 封装 JCI 检测页面的表单验证逻辑，用于验证工程信息输入。
///
/// 需求:
/// - 3.7: 未填写必填项时高亮显示并阻止提交
/// - 3.8: 埋深值为非正数时显示验证错误
library;

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:equatable/equatable.dart';

/// 表单验证状态
///
/// 根据表单输入状态判断验证是否通过。
class FormValidationState extends Equatable {
  /// 创建表单验证状态
  const FormValidationState({
    required this.isRockTypeValid,
    required this.isDepthValid,
    required this.isWaterConditionValid,
  });

  /// 从表单输入值创建验证状态
  ///
  /// [rockType] 岩石种类（null 表示未选择）
  /// [depthText] 埋深输入文本（null 或空表示未填写）
  /// [waterCondition] 地下水状况（null 表示未选择）
  factory FormValidationState.fromInputs({
    RockType? rockType,
    String? depthText,
    WaterCondition? waterCondition,
  }) {
    return FormValidationState(
      isRockTypeValid: rockType != null,
      isDepthValid: _isDepthValid(depthText),
      isWaterConditionValid: waterCondition != null,
    );
  }

  /// 岩石种类是否有效
  final bool isRockTypeValid;

  /// 工程埋深是否有效
  final bool isDepthValid;

  /// 地下水状况是否有效
  final bool isWaterConditionValid;

  /// 表单整体是否有效
  bool get isValid => isRockTypeValid && isDepthValid && isWaterConditionValid;

  /// 获取错误信息列表
  List<String> get errors {
    final result = <String>[];
    if (!isRockTypeValid) result.add('请选择岩石种类');
    if (!isDepthValid) result.add('请输入有效的正数埋深');
    if (!isWaterConditionValid) result.add('请选择地下水状况');
    return result;
  }

  @override
  List<Object?> get props => [
    isRockTypeValid,
    isDepthValid,
    isWaterConditionValid,
  ];

  /// 验证埋深输入是否有效
  ///
  /// 需求 3.8: 埋深值为非正数时验证失败
  static bool _isDepthValid(String? depthText) {
    if (depthText == null || depthText.isEmpty) return false;
    final depth = double.tryParse(depthText);
    if (depth == null) return false;
    return depth > 0;
  }

  /// 公开的埋深验证方法，供外部使用
  static String? validateDepth(String? value) {
    if (value == null || value.isEmpty) return '请输入工程埋深';
    final depth = double.tryParse(value);
    if (depth == null) return '请输入有效的数值';
    if (depth <= 0) return '埋深必须为正数';
    return null;
  }
}
