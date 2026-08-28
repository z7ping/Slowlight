import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

Future<ui.Codec> _decodePng(String path) async {
  final bytes = await File(path).readAsBytes();
  return ui.instantiateImageCodec(bytes);
}

void main() {
  const assets = <String, (int, int)>{
    'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': (48, 48),
    'android/app/src/main/res/mipmap-mdpi/ic_launcher_foreground.png': (108, 108),
    'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': (72, 72),
    'android/app/src/main/res/mipmap-hdpi/ic_launcher_foreground.png': (162, 162),
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': (96, 96),
    'android/app/src/main/res/mipmap-xhdpi/ic_launcher_foreground.png': (216, 216),
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': (144, 144),
    'android/app/src/main/res/mipmap-xxhdpi/ic_launcher_foreground.png': (324, 324),
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': (192, 192),
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': (432, 432),
  };

  test('Android launcher PNG assets are decodable and have expected sizes', () async {
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
}
