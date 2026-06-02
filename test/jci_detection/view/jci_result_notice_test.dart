import 'package:crack_app/jci_detection/view/jci_result_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('result notice explains local auto save and manual sync', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: JciResultNotice(),
        ),
      ),
    );

    expect(
      find.text('本次结果已自动保存到本地记录；联网后可在主页同步本地到网络'),
      findsOneWidget,
    );
  });
}
