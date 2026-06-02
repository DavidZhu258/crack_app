import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  const sourceIconPath = 'assets/app_icon/jinchuan_ai_support_icon.png';

  const launcherSizes = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  test('保留金川岩性支护决策 App 图标源图', () {
    final sourceIcon = File(sourceIconPath);

    expect(sourceIcon.existsSync(), isTrue);

    final decoded = image.decodeImage(sourceIcon.readAsBytesSync());
    expect(decoded, isNotNull);
    expect(decoded!.width, decoded.height);
    expect(decoded.width, greaterThanOrEqualTo(1024));
    expect(_isBlueDominant(decoded), isTrue);
  });

  test('Android manifest 声明普通和圆形启动图标', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:roundIcon="@mipmap/ic_launcher_round"'));
  });

  for (final flavor in ['main', 'staging', 'development']) {
    group('$flavor Android launcher icon', () {
      test('adaptive icon foreground 使用同一张新图标', () {
        final foreground = _decodeLauncherIcon(
          'android/app/src/$flavor/res/drawable/ic_launcher_foreground.png',
        );

        expect(foreground.width, 432);
        expect(foreground.height, 432);
        expect(_isBlueDominant(foreground), isTrue);
        _expectContentInset(
          foreground,
          minimum: 0.14,
          maximum: 0.18,
        );
      });

      for (final entry in launcherSizes.entries) {
        test('${entry.key} PNG 使用新图标且尺寸正确', () {
          final icon = _decodeLauncherIcon(
            'android/app/src/$flavor/res/mipmap-${entry.key}/ic_launcher.png',
          );
          final roundIcon = _decodeLauncherIcon(
            'android/app/src/$flavor/res/mipmap-${entry.key}/'
            'ic_launcher_round.png',
          );

          expect(icon.width, entry.value);
          expect(icon.height, entry.value);
          expect(roundIcon.width, entry.value);
          expect(roundIcon.height, entry.value);
          expect(_isBlueDominant(icon), isTrue);
          expect(_isBlueDominant(roundIcon), isTrue);
          _expectContentInset(
            icon,
            minimum: 0.08,
            maximum: 0.11,
          );
          _expectContentInset(
            roundIcon,
            minimum: 0.08,
            maximum: 0.11,
          );
        });
      }
    });
  }
}

void _expectContentInset(
  image.Image icon, {
  required double minimum,
  required double maximum,
}) {
  final inset = _minimumContentInsetFraction(icon);
  expect(inset, greaterThanOrEqualTo(minimum));
  expect(inset, lessThanOrEqualTo(maximum));
}

image.Image _decodeLauncherIcon(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: path);

  final decoded = image.decodePng(file.readAsBytesSync());
  expect(decoded, isNotNull, reason: path);
  return decoded!;
}

double _minimumContentInsetFraction(image.Image icon) {
  var left = icon.width;
  var top = icon.height;
  var right = icon.width;
  var bottom = icon.height;
  var foundContent = false;

  for (var y = 0; y < icon.height; y += 1) {
    for (var x = 0; x < icon.width; x += 1) {
      final pixel = icon.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final a = pixel.a.toInt();

      if (a <= 16 || (r > 245 && g > 245 && b > 245)) {
        continue;
      }

      foundContent = true;
      if (x < left) left = x;
      if (y < top) top = y;
      if (icon.width - 1 - x < right) right = icon.width - 1 - x;
      if (icon.height - 1 - y < bottom) bottom = icon.height - 1 - y;
    }
  }

  if (!foundContent) {
    return 0;
  }

  final shortestSide = icon.width < icon.height ? icon.width : icon.height;
  final minimumInset = [left, top, right, bottom].reduce(
    (value, element) => value < element ? value : element,
  );
  return minimumInset / shortestSide;
}

bool _isBlueDominant(image.Image icon) {
  var red = 0;
  var green = 0;
  var blue = 0;
  var sampled = 0;

  for (var y = 0; y < icon.height; y += 2) {
    for (var x = 0; x < icon.width; x += 2) {
      final pixel = icon.getPixel(x, y);
      final r = pixel.r.toInt();
      final g = pixel.g.toInt();
      final b = pixel.b.toInt();
      final a = pixel.a.toInt();

      if (a <= 16 || (r > 245 && g > 245 && b > 245)) {
        continue;
      }

      red += r;
      green += g;
      blue += b;
      sampled += 1;
    }
  }

  if (sampled == 0) {
    return false;
  }

  return blue > red && blue > green && blue ~/ sampled > 80;
}
