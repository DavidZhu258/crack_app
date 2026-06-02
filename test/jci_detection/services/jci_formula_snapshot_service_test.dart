import 'dart:convert';
import 'dart:io';

import 'package:crack_app/jci_detection/models/enums.dart';
import 'package:crack_app/jci_detection/services/jci_calculator_service.dart';
import 'package:crack_app/jci_detection/services/jci_formula_snapshot_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canonical formula snapshots match shared golden cases', () {
    final fixture = File('test/fixtures/jci_formula_cases.json');
    final cases =
        (jsonDecode(fixture.readAsStringSync())
                as Map<String, dynamic>)['cases']
            as List<dynamic>;
    final calculator = JciCalculatorService();
    final snapshots = JciFormulaSnapshotService(calculator: calculator);

    for (final entry in cases.cast<Map<String, dynamic>>()) {
      final input = entry['input'] as Map<String, dynamic>;
      final expected = entry['expected'] as Map<String, dynamic>;
      final rockType = RockType.values.firstWhere(
        (type) => type.name == input['rockType'],
      );
      final actual = snapshots.canonicalSnapshot(
        JciInputParameters(
          indicator1: (input['indicator1'] as num).toDouble(),
          indicator2: (input['indicator2'] as num).toDouble(),
          indicator3: (input['indicator3'] as num).toDouble(),
          depth: (input['elevation'] as num).toDouble(),
          ucsMpa: rockType.ucsMpa,
        ),
      );

      expect(actual, expected, reason: entry['name'] as String);
    }
  });
}
