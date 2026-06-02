// Property-test reason strings are split without added whitespace so the
// rendered failure message stays natural in Chinese.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:math';

import 'package:crack_app/crack_detection/cubit/crack_detection_cubit.dart';
import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockCrackDetectionService extends Mock implements CrackDetectionService {}

class MockImagePicker extends Mock implements ImagePicker {}

void main() {
  group('Property 21: 窗口数量限制正确性', () {
    // Feature: jci-calculation, Property 21: 窗口数量限制正确性
    // **Validates: Requirements 13.1, 13.3**
    //
    // 对于任意整数值，setMaxWindows 方法应将窗口数量限制在 1 至 64 之间（含边界）。
    // 当输入值小于 1 时结果为 1，当输入值大于 64 时结果为 64，
    // 当输入值在范围内时保持不变。

    late MockCrackDetectionService mockService;
    late MockImagePicker mockPicker;

    setUp(() {
      mockService = MockCrackDetectionService();
      mockPicker = MockImagePicker();
    });

    test('属性测试: setMaxWindows 将值限制在 [1, 64] 范围内 (200 次迭代)', () async {
      final random = Random(42);
      final cubit = CrackDetectionCubit(
        service: mockService,
        imagePicker: mockPicker,
      );

      for (var i = 0; i < 200; i++) {
        // Generate random integers spanning well below and above [1, 64]
        final value = random.nextInt(300) - 100; // range: [-100, 199]

        cubit.setMaxWindows(value);
        final result = cubit.maxWindows;

        // Core property: result is always in [1, 64]
        expect(
          result >= 1 && result <= 64,
          isTrue,
          reason: '迭代 $i: setMaxWindows($value) → $result，应在 [1, 64] 范围内',
        );

        // Clamping correctness
        if (value < 1) {
          expect(
            result,
            equals(1),
            reason: '迭代 $i: 输入 $value < 1，结果应为 1，实际为 $result',
          );
        } else if (value > 64) {
          expect(
            result,
            equals(64),
            reason: '迭代 $i: 输入 $value > 64，结果应为 64，实际为 $result',
          );
        } else {
          expect(
            result,
            equals(value),
            reason: '迭代 $i: 输入 $value 在 [1, 64] 范围内，结果应保持不变，实际为 $result',
          );
        }
      }

      await cubit.close();
    });

    test('属性测试: 极端负值和极端正值 (100 次迭代)', () async {
      final random = Random(99);
      final cubit = CrackDetectionCubit(
        service: mockService,
        imagePicker: mockPicker,
      );

      for (var i = 0; i < 100; i++) {
        // Generate extreme values
        final extreme = random.nextBool()
            ? -(random.nextInt(1000000) + 1) // large negatives
            : random.nextInt(1000000) + 65; // large positives above 64

        cubit.setMaxWindows(extreme);
        final result = cubit.maxWindows;

        if (extreme < 1) {
          expect(
            result,
            equals(1),
            reason: '迭代 $i: 极端输入 $extreme < 1，结果应为 1',
          );
        } else {
          expect(
            result,
            equals(64),
            reason: '迭代 $i: 极端输入 $extreme > 64，结果应为 64',
          );
        }
      }

      await cubit.close();
    });

    test('属性测试: 边界值验证', () async {
      final cubit = CrackDetectionCubit(
        service: mockService,
        imagePicker: mockPicker,
      );

      // Exact boundaries
      final boundaryTests = <int, int>{
        0: 1, // just below lower bound
        1: 1, // lower bound
        2: 2, // just above lower bound
        63: 63, // just below upper bound
        64: 64, // upper bound
        65: 64, // just above upper bound
        -1: 1, // negative
      };

      for (final entry in boundaryTests.entries) {
        cubit.setMaxWindows(entry.key);
        expect(
          cubit.maxWindows,
          equals(entry.value),
          reason:
              'setMaxWindows(${entry.key}) 应返回 ${entry.value}，'
              '实际为 ${cubit.maxWindows}',
        );
      }

      await cubit.close();
    });
  });
}
