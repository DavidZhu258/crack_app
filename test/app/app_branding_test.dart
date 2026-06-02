import 'dart:io';

import 'package:crack_app/core/app_branding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App 内显示完整系统名，安装包使用短名称', () {
    expect(appSystemName, '金川矿区岩性自适应支护决策系统');
    expect(appLauncherName, '金川岩性支护决策');
  });

  test('production Android flavor 使用短安装名称', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      gradle,
      contains('manifestPlaceholders["appName"] = "金川岩性支护决策"'),
    );
  });
}
