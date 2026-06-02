import 'package:crack_app/jci_detection/view/jci_precision_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows four precision options and defaults to fast mode', (
    tester,
  ) async {
    var selected = 4;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return JciPrecisionSelector(
                selectedMaxWindows: selected,
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('识别精度'), findsOneWidget);
    expect(find.text('快速 4 窗口'), findsOneWidget);
    expect(find.text('标准 8 窗口'), findsOneWidget);
    expect(find.text('精细 12 窗口'), findsOneWidget);
    expect(find.text('最高 20 窗口'), findsOneWidget);
    expect(find.text('低内存优先，适合快速测试和普通手机。'), findsOneWidget);

    await tester.tap(find.text('精细 12 窗口'));
    await tester.pumpAndSettle();

    expect(selected, 12);
    expect(find.text('提升分窗覆盖度，识别更慢、更占内存。'), findsOneWidget);
  });

  testWidgets('uses an in-page segmented control and never pops the route', (
    tester,
  ) async {
    var selected = 4;
    final observer = _RecordingNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return JciPrecisionSelector(
                selectedMaxWindows: selected,
                onChanged: (value) => setState(() => selected = value),
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(SegmentedButton<int>), findsOneWidget);

    await tester.tap(find.text('标准 8 窗口'));
    await tester.pumpAndSettle();

    expect(selected, equals(8));
    expect(observer.popCount, equals(0));
    expect(find.text('识别精度'), findsOneWidget);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}
