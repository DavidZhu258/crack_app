import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/services/support_advisor_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SupportAdvisorService service;

  setUp(() {
    service = const SupportAdvisorService();
  });

  group('SupportAdvisorService - Property 8: 支护方案完整性', () {
    // Feature: jci-calculation, Property 8: 支护方案完整性
    // **Validates: Requirements 7.1-7.3**
    //
    // 对于任意围岩等级，Support_Advisor 返回的支护方案应包含：
    // - 至少一种支护工艺类型
    // - 每种工艺类型应有对应的参数说明

    test('属性测试: 所有围岩等级的支护方案完整性', () {
      for (final grade in RockGrade.values) {
        final plan = service.getSupportPlan(grade);

        // 1. 返回的 SupportPlan 不为 null（类型系统保证）且等级匹配
        expect(
          plan.grade,
          equals(grade),
          reason: '${grade.fullName} 的支护方案等级应匹配',
        );

        // 2. 至少包含一种支护工艺类型（methods 列表非空）
        expect(
          plan.methods,
          isNotEmpty,
          reason: '${grade.fullName} 的支护方案应至少包含一种支护工艺类型',
        );

        // 3. 每种工艺类型应有非空名称和非空参数说明
        for (var j = 0; j < plan.methods.length; j++) {
          final method = plan.methods[j];

          expect(
            method.name,
            isNotEmpty,
            reason: '${grade.fullName} 的第 ${j + 1} 种支护工艺名称不应为空',
          );

          expect(
            method.parameters,
            isNotEmpty,
            reason: '${grade.fullName} 的支护工艺"${method.name}"应有参数说明',
          );
        }
      }
    });
  });

  group('SupportAdvisorService - 金川矿区表 6-11', () {
    test('I-1 类应使用双层喷锚网且不包含钢拱架', () {
      final plan = service.getSupportPlan(RockGrade.i1);

      expect(plan.summary, contains('双层喷锚网'));
      expect(plan.summary, contains('无钢拱架'));
      expect(
        plan.methods.expand((method) => method.parameters.values).join('\n'),
        contains('1.2m×1.2m'),
      );
      expect(
        plan.methods.expand((method) => method.parameters.values).join('\n'),
        contains('200mm×200mm'),
      );
    });

    test('IV 类应使用 U36 钢拱架和超前钎棚参数', () {
      final plan = service.getSupportPlan(RockGrade.iv);
      final text = [
        plan.summary,
        for (final method in plan.methods) ...[
          method.name,
          ...method.parameters.entries.map(
            (entry) => '${entry.key}:${entry.value}',
          ),
        ],
      ].join('\n');

      expect(text, contains('U36直墙拱形'));
      expect(text, contains('间距1.0m'));
      expect(text, contains('超前钎棚'));
      expect(text, contains('150～200mm'));
    });

    test('V 类应包含超前管棚、作业面素喷和超前预注浆', () {
      final plan = service.getSupportPlan(RockGrade.v);
      final text = [
        plan.summary,
        for (final method in plan.methods) ...[
          method.name,
          ...method.parameters.entries.map(
            (entry) => '${entry.key}:${entry.value}',
          ),
        ],
      ].join('\n');

      expect(text, contains('超前管棚'));
      expect(text, contains('作业面素喷'));
      expect(text, contains('超前预注浆'));
      expect(text, contains('厚度≥50mm'));
    });
  });
}
