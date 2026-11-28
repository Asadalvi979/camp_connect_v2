import 'package:camp_connect_v2/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login adapts to mobile and desktop without overflow', (
    tester,
  ) async {
    for (final size in [const Size(390, 844), const Size(1440, 1024)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
    'Registration builds CMS ID from session, course and four-digit number',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MyApp());
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('CMS number')), '44');
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Please correct the highlighted fields above.'),
        findsOneWidget,
      );
      expect(find.text('Enter your four-digit CMS number.'), findsOneWidget);
      expect(find.text('Select your session.'), findsOneWidget);
      expect(find.text('Select your course.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('Session')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('F24').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('Course')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BSSE').last);
      await tester.pumpAndSettle();
      final numberField = find.byKey(const ValueKey('CMS number'));
      await tester.enterText(numberField, '');
      await tester.tap(numberField);
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(numberField);
      expect(field.controller!.text, isEmpty);
      expect(find.text('0044'), findsNothing);
      expect(find.text('Complete CMS ID: F24-BSSE-____'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('CMS number')), '0044');
      await tester.pumpAndSettle();
      expect(find.text('Complete CMS ID: F24-BSSE-0044'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Registration dropdowns fit mobile width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(const ValueKey('Course')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
