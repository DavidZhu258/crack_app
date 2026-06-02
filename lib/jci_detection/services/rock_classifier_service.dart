/// JCI 检测模块 - 围岩等级分类服务
///
/// 根据 JCI 值对围岩进行等级分类，并处理渗水降级逻辑。
///
/// 需求: 5.1-5.7, 6.2, 6.3
library;

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';

/// 围岩等级分类服务
///
/// 提供围岩等级分类和渗水降级功能。
///
/// 分类规则（Property 1: 围岩等级分类正确性）：
/// - JCI > 40: I-1 - 极好
/// - 35 ≤ JCI ≤ 40: I-2 - 好
/// - 30 ≤ JCI < 35: II-1 - 较好
/// - 24 ≤ JCI < 30: II-2 - 一般
/// - 22 ≤ JCI < 24: III - 较差
/// - 16 ≤ JCI < 22: IV - 差
/// - JCI < 16: V - 极差
///
/// 渗水降级规则（Property 2: 渗水降级正确性）：
/// - 存在渗水且原等级不是 V 级时，降低一级
/// - 存在渗水且原等级是 V 级时，保持 V 级
/// - 不存在渗水时，保持原等级
class RockClassifierService {
  /// 根据 JCI 值分类围岩等级
  ///
  /// [jciValue] JCI 值
  ///
  /// 返回对应的围岩等级
  ///
  /// 需求: 5.1-5.7
  RockGrade classify(double jciValue) {
    // 需求 5.1: JCI > 40 → I-1
    if (jciValue > 40) {
      return RockGrade.i1;
    }
    // 需求 5.2: 35 ≤ JCI ≤ 40 → I-2
    if (jciValue >= 35) {
      return RockGrade.i2;
    }
    // 需求 5.3: 30 ≤ JCI < 35 → II-1
    if (jciValue >= 30) {
      return RockGrade.ii1;
    }
    // 需求 5.4: 24 ≤ JCI < 30 → II-2
    if (jciValue >= 24) {
      return RockGrade.ii2;
    }
    // 需求 5.5: 22 ≤ JCI < 24 → III
    if (jciValue >= 22) {
      return RockGrade.iii;
    }
    // 需求 5.6: 16 ≤ JCI < 22 → IV
    if (jciValue >= 16) {
      return RockGrade.iv;
    }
    // 需求 5.7: JCI < 16 → V
    return RockGrade.v;
  }

  /// 应用渗水降级调整
  ///
  /// [originalGrade] 原始围岩等级
  /// [hasSeepage] 是否存在渗水
  ///
  /// 返回包含原始等级、最终等级和降级信息的分类结果
  ///
  /// 需求: 6.2, 6.3
  RockClassificationResult applySeepageAdjustment(
    RockGrade originalGrade, {
    required bool hasSeepage,
  }) {
    // 不存在渗水时，保持原等级
    if (!hasSeepage) {
      return RockClassificationResult(
        originalGrade: originalGrade,
        finalGrade: originalGrade,
      );
    }

    // 需求 6.3: 原等级是 V 级时，保持 V 级不变
    if (originalGrade == RockGrade.v) {
      return RockClassificationResult(
        originalGrade: originalGrade,
        finalGrade: RockGrade.v,
        downgradeReason: '围岩等级已是最低级（V级），无法继续降级',
      );
    }

    // 需求 6.2: 存在渗水时，降低一级
    final downgradedGrade = downgradeOneLevel(originalGrade);
    return RockClassificationResult(
      originalGrade: originalGrade,
      finalGrade: downgradedGrade,
      wasDowngraded: true,
      downgradeReason: '因渗水降级',
    );
  }

  /// 降低一个等级
  ///
  /// [grade] 当前围岩等级
  ///
  /// 返回降低一级后的围岩等级
  /// 如果已经是最低级（V级），则返回 V级
  ///
  /// 等级顺序: I-1 → I-2 → II-1 → II-2 → III → IV → V
  RockGrade downgradeOneLevel(RockGrade grade) {
    return switch (grade) {
      RockGrade.i1 => RockGrade.i2,
      RockGrade.i2 => RockGrade.ii1,
      RockGrade.ii1 => RockGrade.ii2,
      RockGrade.ii2 => RockGrade.iii,
      RockGrade.iii => RockGrade.iv,
      RockGrade.iv => RockGrade.v,
      RockGrade.v => RockGrade.v, // 已是最低级，保持不变
    };
  }
}
