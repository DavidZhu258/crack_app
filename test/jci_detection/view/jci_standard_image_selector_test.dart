import 'package:crack_app/jci_detection/models/standard_image_option.dart';
import 'package:crack_app/jci_detection/view/jci_standard_image_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('标准样图选择器显示三张标准图且不再显示旧默认入口', (tester) async {
    JciStandardImageOption? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JciStandardImageSelector(
            onSelected: (option) => selected = option,
          ),
        ),
      ),
    );

    expect(find.text('选择标准样图'), findsOneWidget);
    expect(find.text('使用默认测试图片'), findsNothing);

    await tester.tap(find.text('选择标准样图'));
    await tester.pumpAndSettle();

    expect(find.text('选择标准掌子面图像'), findsOneWidget);
    expect(find.text('标准样图 1'), findsOneWidget);
    expect(find.text('标准样图 2'), findsOneWidget);
    expect(find.text('标准样图 3'), findsOneWidget);
    expect(find.textContaining('1.jpg'), findsNothing);

    await tester.tap(find.text('标准样图 2'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.assetPath, equals('assets/images/test/14.jpg'));
  });
}
