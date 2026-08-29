import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/services/theme_settings.dart';
import 'package:slowlight/ui/app_theme.dart';

void main() {
  test('Android 字号层级清晰且不提供缩小档', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(AppTheme.textXs, greaterThanOrEqualTo(12));
    expect(AppTheme.textSm, greaterThan(AppTheme.textXs));
    expect(AppTheme.textMd, greaterThan(AppTheme.textSm));
    expect(
      ThemeSettings.fontScaleOptions.keys.every((scale) => scale >= 1),
      isTrue,
    );
  });
}
