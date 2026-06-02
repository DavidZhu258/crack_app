/// JCI 检测模块 - 枚举类型定义
///
/// 包含岩石类型、地下水状况和围岩等级的枚举定义。
/// 这些枚举用于 JCI 计算和围岩分类。
library;

/// 岩石类型枚举
///
/// 定义软件改动文档要求的金川矿区岩性及 UCS。
enum RockType {
  /// 蛇纹大理岩 - UCS 80MPa
  serpentineMarble('蛇纹大理岩', 80),

  /// 中厚层大理岩 - UCS 35MPa
  mediumThickMarble('中厚层大理岩', 35),

  /// 超基性岩 - UCS 40MPa
  ultrabasicRock('超基性岩', 40),

  /// 混合岩 - UCS 25MPa
  mixedRock('混合岩', 25),

  /// 花岗岩 - UCS 28.6MPa
  granite('花岗岩', 28.6),

  /// 黑云母片麻岩 - UCS 30MPa
  biotiteGneiss('黑云母片麻岩', 30);

  const RockType(this.displayName, this.ucsMpa);

  /// 蛇纹大理岩 UCS 常量，供 const JCI 输入使用。
  static const double serpentineMarbleUcs = 80;

  /// 中文显示名称
  final String displayName;

  /// 单轴抗压强度（MPa）
  final double ucsMpa;
}

/// 地下水状况枚举
///
/// 定义地下水状况及其影响系数。
/// 影响系数用于 JCI 计算中的地下水评分。
///
/// 需求: 3.3 - 提供地下水状况选择，包含"干燥"、"潮湿"、"滴水"、"涌水"等选项
enum WaterCondition {
  /// 干燥 - 系数 1.0
  dry('干燥', 1),

  /// 潮湿 - 系数 0.9
  damp('潮湿', 0.9),

  /// 滴水 - 系数 0.7
  dripping('滴水', 0.7),

  /// 涌水 - 系数 0.5
  flowing('涌水', 0.5);

  const WaterCondition(this.displayName, this.factor);

  /// 中文显示名称
  final String displayName;

  /// 影响系数，用于 JCI 计算
  final double factor;
}

/// 围岩等级枚举
///
/// 根据 JCI 值范围定义围岩等级。
/// 每个等级包含名称、描述和 JCI 值范围。
///
/// 需求: 5.1-5.7 - 围岩等级分类标准
/// - JCI > 40: I-1 - 极好
/// - 35 ≤ JCI ≤ 40: I-2 - 好
/// - 30 ≤ JCI < 35: II-1 - 较好
/// - 24 ≤ JCI < 30: II-2 - 一般
/// - 22 ≤ JCI < 24: III - 较差
/// - 16 ≤ JCI < 22: IV - 差
/// - JCI < 16: V - 极差
enum RockGrade {
  /// I-1 - 极好 (JCI > 40)
  i1('I-1', '极好', 40, double.infinity),

  /// I-2 - 好 (35 ≤ JCI ≤ 40)
  i2('I-2', '好', 35, 40),

  /// II-1 - 较好 (30 ≤ JCI < 35)
  ii1('II-1', '较好', 30, 35),

  /// II-2 - 一般 (24 ≤ JCI < 30)
  ii2('II-2', '一般', 24, 30),

  /// III - 较差 (22 ≤ JCI < 24)
  iii('III', '较差', 22, 24),

  /// IV - 差 (16 ≤ JCI < 22)
  iv('IV', '差', 16, 22),

  /// V - 极差 (JCI < 16)
  v('V', '极差', double.negativeInfinity, 16);

  const RockGrade(this.name, this.description, this.minJci, this.maxJci);

  /// 等级名称（如"I-1"）
  final String name;

  /// 等级描述（如"极好"）
  final String description;

  /// JCI 最小值（包含）
  final double minJci;

  /// JCI 最大值（不包含，除了 i1 和 i2 的上边界）
  final double maxJci;

  /// 获取完整的显示名称（等级名称 + 描述）
  String get fullName => '$name - $description';
}
