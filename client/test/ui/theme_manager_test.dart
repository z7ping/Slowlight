import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/theme_manager.dart';

void main() {
  group('ThemeManager', () {
    test('should have lightTheme getter returning ThemeData', () {
      expect(ThemeManager.lightTheme, isA<ThemeData>());
    });

    test('should have darkTheme getter returning ThemeData', () {
      expect(ThemeManager.darkTheme, isA<ThemeData>());
    });

    test('should have primary color getter', () {
      expect(ThemeManager.primary, isA<Color>());
    });

    test('should have background color getter', () {
      expect(ThemeManager.background, isA<Color>());
    });

    test('should have foreground color getter', () {
      expect(ThemeManager.foreground, isA<Color>());
    });
  });
}
