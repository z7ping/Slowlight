import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/responsive_layout.dart';

void main() {
  group('ResponsiveLayout', () {
    test('should have gridColumns method', () {
      expect(ResponsiveLayout.gridColumns, isA<Function>());
    });
  });
}
