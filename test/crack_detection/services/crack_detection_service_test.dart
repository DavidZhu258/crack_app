import 'dart:typed_data';

import 'package:crack_app/crack_detection/services/crack_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs full local detection in a background isolate by default', () {
    final service = CrackDetectionService();

    expect(service.runsLocalDetectionInIsolateForTest, isTrue);
  });

  test('can opt out of background local detection for diagnostics', () {
    final service = CrackDetectionService(runLocalDetectionInIsolate: false);

    expect(service.runsLocalDetectionInIsolateForTest, isFalse);
  });

  test(
    'background isolate request does not capture unsendable ports',
    () async {
      final service = CrackDetectionService();

      await service.loadModelFromBytes(Uint8List.fromList(<int>[0, 1, 2, 3]));

      await expectLater(
        service.detectCrack(
          'missing-image.jpg',
          onProgress: (_, _, _) {},
        ),
        throwsA(
          isNot(
            predicate<Object>(
              (error) => '$error'.contains('unsendable'),
              'an isolate unsendable-object error',
            ),
          ),
        ),
      );
    },
  );

  test(
    'configured inference policy yields after every inference window',
    () async {
      final delays = <Duration>[];
      final service = CrackDetectionService(
        executionPolicy: const InferenceExecutionPolicy(
          windowCooldown: Duration(milliseconds: 120),
        ),
        delay: (duration) async => delays.add(duration),
      );

      await service.yieldAfterInferenceWindowForTest(current: 1, total: 4);

      expect(delays, equals([const Duration(milliseconds: 120)]));
    },
  );

  test('inference policy identifies CPU-heavy row chunks for yielding', () {
    const policy = InferenceExecutionPolicy(cpuChunkRows: 8);

    expect(policy.shouldYieldAfterCpuRows(0), isFalse);
    expect(policy.shouldYieldAfterCpuRows(7), isFalse);
    expect(policy.shouldYieldAfterCpuRows(8), isTrue);
    expect(policy.shouldYieldAfterCpuRows(16), isTrue);
  });

  test(
    'configured inference policy yields during CPU-heavy row work',
    () async {
      final delays = <Duration>[];
      final service = CrackDetectionService(
        executionPolicy: const InferenceExecutionPolicy(
          cpuChunkRows: 8,
          cpuChunkCooldown: Duration(milliseconds: 5),
        ),
        delay: (duration) async => delays.add(duration),
      );

      await service.yieldDuringCpuWorkForTest(processedRows: 7);
      await service.yieldDuringCpuWorkForTest(processedRows: 8);

      expect(delays, equals([const Duration(milliseconds: 5)]));
    },
  );
}
