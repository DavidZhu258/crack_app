import 'package:crack_app/jci_detection/models/crack_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CrackInfo', () {
    test('应该正确创建实例并存储所有字段', () {
      const crack = CrackInfo(
        id: 1,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );

      expect(crack.id, equals(1));
      expect(crack.lengthCm, equals(15.5));
      expect(crack.lengthPixels, equals(310));
      expect(crack.x, equals(10));
      expect(crack.y, equals(20));
      expect(crack.w, equals(100));
      expect(crack.h, equals(50));
    });

    test('应该支持 Equatable 值相等比较', () {
      const crack1 = CrackInfo(
        id: 1,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );
      const crack2 = CrackInfo(
        id: 1,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );
      const crack3 = CrackInfo(
        id: 2,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );

      expect(crack1, equals(crack2));
      expect(crack1, isNot(equals(crack3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = CrackInfo(
        id: 1,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );

      final updated = original.copyWith(lengthCm: 20, id: 2);

      expect(updated.id, equals(2));
      expect(updated.lengthCm, equals(20.0));
      expect(updated.lengthPixels, equals(310));
      expect(updated.x, equals(10));
      expect(updated.y, equals(20));
      expect(updated.w, equals(100));
      expect(updated.h, equals(50));
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = CrackInfo(
        id: 1,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const crack = CrackInfo(
        id: 1,
        lengthCm: 15.5,
        lengthPixels: 310,
        x: 10,
        y: 20,
        w: 100,
        h: 50,
      );

      expect(crack.props, equals([1, 15.5, 310, 10, 20, 100, 50]));
    });
  });

  group('CrackIdentificationResult', () {
    test('应该正确创建实例并存储所有字段', () {
      const cracks = [
        CrackInfo(
          id: 1,
          lengthCm: 30,
          lengthPixels: 600,
          x: 10,
          y: 20,
          w: 100,
          h: 50,
        ),
        CrackInfo(
          id: 2,
          lengthCm: 15,
          lengthPixels: 300,
          x: 50,
          y: 60,
          w: 80,
          h: 40,
        ),
      ];

      const result = CrackIdentificationResult(
        cracks: cracks,
        totalLengthCm: 45,
        averageLengthCm: 22.5,
      );

      expect(result.cracks.length, equals(2));
      expect(result.totalLengthCm, equals(45.0));
      expect(result.averageLengthCm, equals(22.5));
    });

    test('应该支持空裂缝列表', () {
      const result = CrackIdentificationResult(
        cracks: [],
        totalLengthCm: 0,
        averageLengthCm: 0,
      );

      expect(result.cracks, isEmpty);
      expect(result.totalLengthCm, equals(0));
      expect(result.averageLengthCm, equals(0));
    });

    test('应该支持 Equatable 值相等比较', () {
      const cracks = [
        CrackInfo(
          id: 1,
          lengthCm: 30,
          lengthPixels: 600,
          x: 10,
          y: 20,
          w: 100,
          h: 50,
        ),
      ];

      const result1 = CrackIdentificationResult(
        cracks: cracks,
        totalLengthCm: 30,
        averageLengthCm: 30,
      );
      const result2 = CrackIdentificationResult(
        cracks: cracks,
        totalLengthCm: 30,
        averageLengthCm: 30,
      );
      const result3 = CrackIdentificationResult(
        cracks: cracks,
        totalLengthCm: 50,
        averageLengthCm: 50,
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('copyWith 应该正确创建副本并更新指定字段', () {
      const original = CrackIdentificationResult(
        cracks: [
          CrackInfo(
            id: 1,
            lengthCm: 30,
            lengthPixels: 600,
            x: 10,
            y: 20,
            w: 100,
            h: 50,
          ),
        ],
        totalLengthCm: 30,
        averageLengthCm: 30,
      );

      final updated = original.copyWith(totalLengthCm: 60);

      expect(updated.cracks.length, equals(1));
      expect(updated.totalLengthCm, equals(60.0));
      expect(updated.averageLengthCm, equals(30.0));
    });

    test('copyWith 不传参数应返回等价实例', () {
      const original = CrackIdentificationResult(
        cracks: [
          CrackInfo(
            id: 1,
            lengthCm: 30,
            lengthPixels: 600,
            x: 10,
            y: 20,
            w: 100,
            h: 50,
          ),
        ],
        totalLengthCm: 30,
        averageLengthCm: 30,
      );

      final copy = original.copyWith();

      expect(copy, equals(original));
    });

    test('props 应包含所有字段', () {
      const cracks = <CrackInfo>[];
      const result = CrackIdentificationResult(
        cracks: cracks,
        totalLengthCm: 45,
        averageLengthCm: 22.5,
      );

      expect(result.props, equals([cracks, 45.0, 22.5]));
    });
  });
}
