/// JCI 检测模块 - 支护方案建议服务
///
/// 根据软件改动文档中的“矿山工程公司岩体类别与施工及支护参数”
/// 为七级围岩返回金川矿区支护方案。
library;

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/models/models.dart';

/// 支护方案建议服务
class SupportAdvisorService {
  /// 创建支护方案建议服务实例
  const SupportAdvisorService();

  static const String _commonRemark =
      '巷道或岔口高度超过6m时必须对拱部进行长锚索加固；'
      '施工7m及以上巷道或硐室时，拱部二次支护后必须补打加密网。';

  /// 金川矿区支护方案数据库
  static const Map<RockGrade, SupportPlan> _supportDatabase = {
    RockGrade.i1: SupportPlan(
      grade: RockGrade.i1,
      methods: [
        SupportMethod(
          name: '长台阶法/短台阶法',
          parameters: {
            '适用岩体': 'I-1类岩石，工程地质条件极好',
            '岩体特征': '块状结构，整体完整性极高，节理裂隙极不发育',
          },
        ),
        SupportMethod(
          name: '双层喷锚网支护（无钢拱架）',
          parameters: {
            '锚杆间排距': '1.2m×1.2m（体积配筋率降低31%）',
            '钢筋网': 'Φ6.5圆钢点焊，网格200mm×200mm',
            '喷射混凝土': '双层总厚200mm（C25）',
          },
        ),
      ],
      summary: 'I-1类围岩极好，采用长台阶法或短台阶法，双层喷锚网支护，无钢拱架。',
    ),
    RockGrade.i2: SupportPlan(
      grade: RockGrade.i2,
      methods: [
        SupportMethod(
          name: '长台阶法/短台阶法',
          parameters: {
            '适用岩体': 'I-2类岩石，工程地质条件好',
            '岩体特征': '块状或层状结构，完整性较好，以节理为主发育但密度较低',
          },
        ),
        SupportMethod(
          name: '双层喷锚网支护（无钢拱架）',
          parameters: {
            '锚杆间排距': '1.0m×1.0m',
            '钢筋网': 'Φ6.5圆钢点焊，网格150mm×150mm',
            '喷射混凝土': '双层总厚200mm（C25）',
          },
        ),
      ],
      summary: 'I-2类围岩好，采用长台阶法或短台阶法，双层喷锚网支护，无钢拱架。',
    ),
    RockGrade.ii1: SupportPlan(
      grade: RockGrade.ii1,
      methods: [
        SupportMethod(
          name: '短台阶法',
          parameters: {
            '适用岩体': 'II-1类岩石，工程地质条件较好',
            '施工工艺': '双层喷锚网 + 二次支护架设U钢拱架 + 锚注（可选）',
          },
        ),
        SupportMethod(
          name: '双层喷锚网 + 二次U钢拱架 + 锚注（可选）',
          parameters: {
            '锚杆间排距': '1.2m×1.0m',
            '钢筋网': 'Φ6.5圆钢点焊，网格150mm×150mm',
            '钢拱架': 'U36直墙拱形，间距1.2m（等效刚度降低17%）',
            '喷射混凝土': '双层总厚200mm（C25）',
          },
        ),
      ],
      summary: 'II-1类围岩较好，短台阶法，双层喷锚网配合二次U36钢拱架，必要时锚注。',
    ),
    RockGrade.ii2: SupportPlan(
      grade: RockGrade.ii2,
      methods: [
        SupportMethod(
          name: '短台阶法',
          parameters: {
            '适用岩体': 'II-2类岩石，工程地质条件一般',
            '施工工艺': '双层喷锚网 + 二次支护架设U钢拱架 + 锚注（可选）',
          },
        ),
        SupportMethod(
          name: '双层喷锚网 + 二次U钢拱架 + 锚注（可选）',
          parameters: {
            '锚杆间排距': '1.0m×1.0m',
            '钢筋网': 'Φ6.5圆钢点焊，网格150mm×150mm',
            '钢拱架': 'U36直墙拱形，间距1.0m',
            '喷射混凝土': '双层总厚200mm（C25）',
          },
        ),
      ],
      summary: 'II-2类围岩一般，短台阶法，双层喷锚网配合二次U36钢拱架，必要时锚注。',
    ),
    RockGrade.iii: SupportPlan(
      grade: RockGrade.iii,
      methods: [
        SupportMethod(
          name: '短台阶法',
          parameters: {
            '适用岩体': 'III类岩石，工程地质条件较差',
            '施工工艺': '双层喷锚网 + 一次支护架设U钢拱架 + 锚注（可选）',
          },
        ),
        SupportMethod(
          name: '双层喷锚网 + 一次U钢拱架 + 锚注（可选）',
          parameters: {
            '锚杆间排距': '1.0m×1.0m',
            '钢筋网': 'Φ6.5圆钢点焊，网格150mm×150mm',
            '注浆锚杆': 'Φ32×6mm无缝钢管，L=2.5m，间排距2.0m×2.0m',
            '钢拱架': 'U36直墙拱形，间距1.2m，每拱腿3组（6根）Φ18锚杆固定',
            '喷射混凝土': '双层总厚200mm（C25）',
            '超前钎棚': '间距150～200mm，每拱不少于15根（必要时）',
          },
        ),
      ],
      summary: 'III类围岩较差，短台阶法，双层喷锚网配合一次U36钢拱架，必要时锚注和超前钎棚。',
    ),
    RockGrade.iv: SupportPlan(
      grade: RockGrade.iv,
      methods: [
        SupportMethod(
          name: '短台阶法',
          parameters: {
            '适用岩体': 'IV类岩石，工程地质条件差',
            '施工工艺': '双层喷锚网 + 一次支护架设U钢拱架 + 超前钎棚 + 锚注（可选）',
          },
        ),
        SupportMethod(
          name: '双层喷锚网 + 一次U钢拱架 + 超前钎棚 + 锚注（可选）',
          parameters: {
            '锚杆间排距': '1.0m×1.0m',
            '钢筋网': 'Φ6.5圆钢点焊，网格150mm×150mm',
            '注浆锚杆': 'Φ32×6mm无缝钢管，L=2.5m，间排距2.0m×2.0m',
            '钢拱架': 'U36直墙拱形，间距1.0m，每拱腿3组（6根）Φ18锚杆固定',
            '喷射混凝土': '双层总厚200mm（C25）',
            '超前钎棚': '间距150～200mm，每拱不少于15根',
          },
        ),
      ],
      summary: 'IV类围岩差，短台阶法，双层喷锚网配合一次U36钢拱架、超前钎棚和锚注。',
    ),
    RockGrade.v: SupportPlan(
      grade: RockGrade.v,
      methods: [
        SupportMethod(
          name: '微倾法',
          parameters: {
            '适用岩体': 'V类岩石，工程地质条件极差',
            '施工工艺': '双层喷锚网 + 一次U钢拱架 + 超前管棚 + 作业面素喷 + 超前预注浆 + 锚注（可选）',
          },
        ),
        SupportMethod(
          name: '双层喷锚网 + 一次U钢拱架',
          parameters: {
            '锚杆间排距': '1.0m×1.0m',
            '钢筋网': 'Φ6.5圆钢点焊，网格150mm×150mm',
            '注浆锚杆': 'Φ32×6mm无缝钢管，L=2.5m，间排距2.0m×2.0m',
            '钢拱架': 'U36直墙拱形，间距1.0m，悬空不超过2付',
            '喷射混凝土': '双层总厚200mm（C25）',
          },
        ),
        SupportMethod(
          name: '超前管棚 + 作业面素喷 + 超前预注浆',
          parameters: {
            '超前管棚': '按原标准，必要时预注浆',
            '作业面素喷': '厚度≥50mm（封闭）',
            '超前预注浆': '拱梁上部均匀分布3～4根注浆锚杆，每2付拱架一次',
          },
        ),
      ],
      summary: 'V类围岩极差，微倾法，双层喷锚网、一次U36钢拱架、超前管棚、作业面素喷、超前预注浆和锚注组合支护。',
    ),
  };

  /// 获取支护方案
  SupportPlan getSupportPlan(RockGrade grade) {
    final plan = _supportDatabase[grade];

    if (plan != null) {
      return _withCommonRemark(plan);
    }

    return SupportPlan(
      grade: grade,
      methods: const [
        SupportMethod(
          name: '待定',
          parameters: {
            '说明': '暂无具体方案，请咨询专业人员',
          },
        ),
      ],
      summary: '暂无具体方案，请咨询专业人员',
      isPlaceholder: true,
    );
  }

  SupportPlan _withCommonRemark(SupportPlan plan) {
    return plan.copyWith(summary: '${plan.summary} $_commonRemark');
  }
}
