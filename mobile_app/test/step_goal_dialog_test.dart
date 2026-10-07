import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ov_watch_app/features/settings/presentation/step_goal_dialog.dart';

void main() {
  testWidgets('shows the saved goal and submits an edited valid goal', (
    tester,
  ) async {
    final saved = <int>[];
    await _openDialog(
      tester,
      initialGoal: 12000,
      onSave: (goal) async {
        saved.add(goal);
        return true;
      },
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '12000',
    );

    await tester.enterText(find.byType(TextField), '15000');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(saved, [15000]);
    expect(find.byType(StepGoalDialog), findsNothing);
  });

  for (final goal in [1000, 50000]) {
    testWidgets('keyboard submission accepts boundary goal $goal', (
      tester,
    ) async {
      final saved = <int>[];
      await _openDialog(
        tester,
        onSave: (value) async {
          saved.add(value);
          return true;
        },
      );

      await tester.enterText(find.byType(TextField), '$goal');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(saved, [goal]);
      expect(find.byType(StepGoalDialog), findsNothing);
    });
  }

  for (final invalid in ['', '999', '50001']) {
    testWidgets('invalid goal "$invalid" stays open without saving', (
      tester,
    ) async {
      var saveCount = 0;
      await _openDialog(
        tester,
        onSave: (_) async {
          saveCount++;
          return true;
        },
      );

      await tester.enterText(find.byType(TextField), invalid);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();

      expect(saveCount, 0);
      expect(find.byType(StepGoalDialog), findsOneWidget);
      expect(find.text('请输入 1,000–50,000 之间的整数'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    });
  }

  testWidgets('failed persistence displays an error and allows retry', (
    tester,
  ) async {
    final saved = <int>[];
    await _openDialog(
      tester,
      onSave: (goal) async {
        saved.add(goal);
        return saved.length > 1;
      },
    );

    await tester.enterText(find.byType(TextField), '18000');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.byType(StepGoalDialog), findsOneWidget);
    expect(find.text('保存失败，请重试'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '18000',
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(saved, [18000, 18000]);
    expect(find.byType(StepGoalDialog), findsNothing);
  });

  testWidgets(
    'pending save disables edits and ignores rapid repeated submissions',
    (tester) async {
      final completion = Completer<bool>();
      final saved = <int>[];
      await _openDialog(
        tester,
        onSave: (goal) {
          saved.add(goal);
          return completion.future;
        },
      );
      await tester.enterText(find.byType(TextField), '16000');

      // Repeated taps before the next build exercise the handler's own guard.
      final saveButton = find.byType(FilledButton);
      await tester.tap(saveButton);
      await tester.tap(saveButton);
      await tester.pump();

      expect(saved, [16000]);
      expect(find.text('保存中…'), findsOneWidget);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.byType(StepGoalDialog), findsOneWidget);

      completion.complete(true);
      await tester.pumpAndSettle();
      expect(saved, [16000]);
      expect(find.byType(StepGoalDialog), findsNothing);
    },
  );

  testWidgets('cancel leaves the stored goal untouched', (tester) async {
    var saveCount = 0;
    await _openDialog(
      tester,
      onSave: (_) async {
        saveCount++;
        return true;
      },
    );

    await tester.enterText(find.byType(TextField), '20000');
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(saveCount, 0);
    expect(find.byType(StepGoalDialog), findsNothing);
  });
}

Future<void> _openDialog(
  WidgetTester tester, {
  int initialGoal = 8000,
  required Future<bool> Function(int value) onSave,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  StepGoalDialog(initialGoal: initialGoal, onSave: onSave),
            ),
            child: const Text('Open goal'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open goal'));
  await tester.pumpAndSettle();
}
