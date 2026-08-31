import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/ui/fx.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Windows Material 与 Shad Theme 使用桌面高密度字号', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;

    final material = AppTheme.lightTheme();
    final shad = shadLightTheme();

    expect(
      material.textTheme.titleLarge?.fontSize,
      SlowlightTypography.desktopPageTitleSize,
    );
    expect(
      material.textTheme.bodyLarge?.fontSize,
      SlowlightTypography.desktopBodySize,
    );
    expect(
      material.textTheme.labelLarge?.fontSize,
      SlowlightTypography.desktopButtonSize,
    );
    expect(
      shad.textTheme.p.fontSize,
      SlowlightTypography.desktopBodySize,
    );
    expect(
      shad.textTheme.small.fontSize,
      SlowlightTypography.desktopButtonSize,
    );
  });

  test('Android Material 与 Shad Theme 使用移动端可读字号', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final material = AppTheme.lightTheme();
    final shad = shadLightTheme();

    expect(
      material.textTheme.titleLarge?.fontSize,
      SlowlightTypography.pageTitleSize,
    );
    expect(
      material.textTheme.bodyLarge?.fontSize,
      SlowlightTypography.bodySize,
    );
    expect(
      material.textTheme.labelLarge?.fontSize,
      SlowlightTypography.buttonSize,
    );
    expect(shad.textTheme.p.fontSize, SlowlightTypography.bodySize);
    expect(shad.textTheme.small.fontSize, SlowlightTypography.buttonSize);
  });
}
