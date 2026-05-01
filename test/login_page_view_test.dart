import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seshly/features/login/view/login_page_view.dart';

void main() {
  testWidgets('Instant Tutor card does not overflow at 280px width', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0F142B),
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Center(
              child: LoginInstantTutorModeCard(
                primaryColor: const Color(0xFF00C09E),
                isDisabled: false,
                isBusy: false,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Instant Tutor Mode'), findsOneWidget);
    expect(find.text('Continue in Instant Tutor Mode'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
