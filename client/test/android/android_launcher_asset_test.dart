import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Codec> _decodePng(String path) async {
  final bytes = await File(path).readAsBytes();
  return ui.instantiateImageCodec(bytes);
}

Future<({double widthDp, double heightDp, double maxRadiusDp})>
    _measureForeground(String path) async {
  final codec = await _decodePng(path);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final imageWidth = image.width;
  final imageHeight = image.height;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    image.dispose();
    codec.dispose();
    throw StateError('$path: 无法读取 RGBA 像素');
  }

  var minX = imageWidth;
  var minY = imageHeight;
  var maxX = -1;
  var maxY = -1;
  var maxRadiusDp = 0.0;
  final rgba = bytes.buffer.asUint8List();
  for (var y = 0; y < imageHeight; y++) {
    for (var x = 0; x < imageWidth; x++) {
      final alpha = rgba[(y * imageWidth + x) * 4 + 3];
      if (alpha <= 15) continue;
      minX = x < minX ? x : minX;
      minY = y < minY ? y : minY;
      maxX = x > maxX ? x : maxX;
      maxY = y > maxY ? y : maxY;

      final dx = (x + 0.5) * 108 / imageWidth - 54;
      final dy = (y + 0.5) * 108 / imageHeight - 54;
      final radiusDp = math.sqrt(dx * dx + dy * dy);
      maxRadiusDp = radiusDp > maxRadiusDp ? radiusDp : maxRadiusDp;
    }
  }
  image.dispose();
  codec.dispose();

  if (maxX < minX || maxY < minY) {
    throw StateError('$path: 前景图标没有可见像素');
  }
  return (
    widthDp: (maxX - minX + 1) * 108 / imageWidth,
    heightDp: (maxY - minY + 1) * 108 / imageHeight,
    maxRadiusDp: maxRadiusDp,
  );
}

void main() {
  const assets = <String, (int, int)>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': (48, 48),
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': (
      108,
      108
    ),
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': (72, 72),
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png': (
      162,
      162
    ),
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': (96, 96),
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png': (
      216,
      216
    ),
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': (144, 144),
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png': (
      324,
      324
    ),
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': (192, 192),
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': (
      432,
      432
    ),
  };

  test('Android launcher PNG assets are decodable and have expected sizes',
      () async {
    for (final entry in assets.entries) {
      ui.Codec? codec;
      ui.FrameInfo? frame;
      try {
        codec = await _decodePng(entry.key);
        frame = await codec.getNextFrame();
      } catch (error) {
        fail('${entry.key}: $error');
      }
      addTearDown(codec!.dispose);
      expect(frame!.image.width, entry.value.$1, reason: entry.key);
      expect(frame.image.height, entry.value.$2, reason: entry.key);
      frame.image.dispose();
    }
  });

  test('Android 自适应图标前景保持在 66dp 安全区且各密度构图一致', () async {
    final measurements =
        <({double widthDp, double heightDp, double maxRadiusDp})>[];
    for (final path
        in assets.keys.where((path) => path.contains('foreground'))) {
      final measurement = await _measureForeground(path);
      measurements.add(measurement);
      expect(measurement.widthDp, lessThanOrEqualTo(66), reason: path);
      expect(measurement.heightDp, lessThanOrEqualTo(66), reason: path);
      expect(measurement.maxRadiusDp, lessThanOrEqualTo(33), reason: path);
    }

    final widths = measurements.map((value) => value.widthDp);
    final heights = measurements.map((value) => value.heightDp);
    expect(
      widths.reduce(math.max) - widths.reduce(math.min),
      lessThanOrEqualTo(1),
    );
    expect(
      heights.reduce(math.max) - heights.reduce(math.min),
      lessThanOrEqualTo(1),
    );
  });
}
