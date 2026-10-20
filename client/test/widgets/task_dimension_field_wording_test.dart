import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slowlight/widgets/task_dimension_field.dart';

import '../support/fx_test_host.dart';

void main() {
  testWidgets('四维身份保持独立的选择语义，不混称标签', (tester) async {
    String? selected;
    await tester.pumpWidget(buildFxTestHost(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TaskDimensionField(
            selectedKey: selected,
            onChanged: (value) => setState(() => selected = value),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('四维身份（可选）'), findsOneWidget);
    expect(find.text('归属维度（可选）'), findsNothing);
    await disposeFxTestHost(tester);
  });
}
