import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 主程序图标包含完整响应式尺寸', () {
    final windowBytes =
        File('windows/runner/resources/app_icon.ico').readAsBytesSync();

    final frames = _readIcoFrames(windowBytes);
    expect(
      frames.map((frame) => frame.size).toList(),
      [16, 20, 24, 32, 40, 48, 64, 96, 128, 256],
    );
    expect(frames.every((frame) => frame.bitsPerPixel == 32), isTrue);
    expect(frames.every((frame) => frame.pngEncoded), isTrue);
  });

  test('Windows 托盘图标与主程序图标使用不同的响应式资产', () {
    final windowBytes =
        File('windows/runner/resources/app_icon.ico').readAsBytesSync();
    final trayBytes = File('assets/app_icon.ico').readAsBytesSync();

    expect(windowBytes, isNotEmpty);
    expect(trayBytes, isNotEmpty);
    expect(trayBytes, isNot(orderedEquals(windowBytes)));

    final trayFrames = _readIcoFrames(trayBytes);
    expect(trayFrames, isNotEmpty);
    expect(trayFrames.any((frame) => frame.size == 16), isTrue);
    expect(trayFrames.any((frame) => frame.size == 32), isTrue);
    expect(trayFrames.every((frame) => frame.bitsPerPixel == 32), isTrue);
    expect(trayFrames.every((frame) => frame.pngEncoded), isTrue);
  });
}

List<_IcoFrame> _readIcoFrames(Uint8List bytes) {
  expect(bytes.length, greaterThanOrEqualTo(6));
  final data = ByteData.sublistView(bytes);
  expect(data.getUint16(0, Endian.little), 0);
  expect(data.getUint16(2, Endian.little), 1);
  final count = data.getUint16(4, Endian.little);
  expect(count, greaterThan(0));

  final frames = <_IcoFrame>[];
  for (var index = 0; index < count; index++) {
    final entry = 6 + index * 16;
    expect(entry + 16, lessThanOrEqualTo(bytes.length));
    final rawWidth = data.getUint8(entry);
    final rawHeight = data.getUint8(entry + 1);
    final width = rawWidth == 0 ? 256 : rawWidth;
    final height = rawHeight == 0 ? 256 : rawHeight;
    expect(height, width);
    final bitsPerPixel = data.getUint16(entry + 6, Endian.little);
    final byteCount = data.getUint32(entry + 8, Endian.little);
    final offset = data.getUint32(entry + 12, Endian.little);
    expect(offset + byteCount, lessThanOrEqualTo(bytes.length));
    expect(byteCount, greaterThanOrEqualTo(4));
    final pngEncoded = bytes[offset] == 0x89 &&
        bytes[offset + 1] == 0x50 &&
        bytes[offset + 2] == 0x4E &&
        bytes[offset + 3] == 0x47;
    frames.add(_IcoFrame(width, bitsPerPixel, pngEncoded));
  }
  return frames;
}

class _IcoFrame {
  final int size;
  final int bitsPerPixel;
  final bool pngEncoded;

  const _IcoFrame(this.size, this.bitsPerPixel, this.pngEncoded);
}
