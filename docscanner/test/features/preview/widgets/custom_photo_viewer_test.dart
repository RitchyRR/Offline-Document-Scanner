import 'dart:math' as math;

import 'package:docscanner/features/preview/widgets/custom_photo_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preserves an external transform when the image changes', (
    tester,
  ) async {
    final controller = TransformationController(
      Matrix4.identity()
        ..scaleByDouble(2, 2, 2, 1)
        ..translateByDouble(-80, -120, 0, 1),
    );

    Widget viewer(String imagePath) {
      return MaterialApp(
        home: Scaffold(
          body: CustomPhotoViewer(
            imagePath: imagePath,
            imageSize: const Size(400, 400),
            transformationController: controller,
            child: const ColoredBox(color: Colors.black),
          ),
        ),
      );
    }

    await tester.pumpWidget(viewer('first'));
    final expectedTransform = Matrix4.copy(controller.value);

    await tester.pumpWidget(viewer('second'));

    expect(controller.value, expectedTransform);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('dampens rotation with an ease-in and ease-out curve', (
    tester,
  ) async {
    final gestures = await _startRotationGesture(tester);

    await _movePointersToAngle(
      tester,
      gestures.$1,
      gestures.$2,
      95 * math.pi / 180,
    );
    final smallRotation = _visualRotation(tester);

    await _movePointersToAngle(
      tester,
      gestures.$1,
      gestures.$2,
      135 * math.pi / 180,
    );
    final mediumRotation = _visualRotation(tester);

    await _movePointersToAngle(tester, gestures.$1, gestures.$2, math.pi);
    final largeRotation = _visualRotation(tester);

    expect(smallRotation, lessThan(1 * math.pi / 180));
    expect(mediumRotation, greaterThan(smallRotation));
    expect(largeRotation, greaterThan(mediumRotation));
    expect(largeRotation, lessThanOrEqualTo(30 * math.pi / 180));

    await gestures.$1.up();
    await gestures.$2.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'keeps rotation continuous when vertically arranged pointers swap',
    (tester) async {
      final gestures = await _startRotationGesture(tester);

      await _movePointersToAngle(
        tester,
        gestures.$1,
        gestures.$2,
        179 * math.pi / 180,
      );
      final angleBeforeWrap = _visualRotation(tester);

      await _movePointersToAngle(
        tester,
        gestures.$1,
        gestures.$2,
        -179 * math.pi / 180,
      );
      final angleAfterWrap = _visualRotation(tester);

      expect(angleBeforeWrap, greaterThan(0));
      expect(angleAfterWrap, greaterThan(angleBeforeWrap));
      expect(angleAfterWrap - angleBeforeWrap, lessThan(0.1));

      await gestures.$1.up();
      await gestures.$2.up();
      await tester.pumpAndSettle();
    },
  );
}

Future<(TestGesture, TestGesture)> _startRotationGesture(
  WidgetTester tester,
) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 400,
          child: CustomPhotoViewer(
            imagePath: '',
            imageSize: Size(400, 400),
            child: ColoredBox(color: Colors.black),
          ),
        ),
      ),
    ),
  );

  final firstPointer = await tester.createGesture(pointer: 1);
  final secondPointer = await tester.createGesture(pointer: 2);
  await firstPointer.down(const Offset(200, 100));
  await secondPointer.down(const Offset(200, 300));
  await tester.pump();
  return (firstPointer, secondPointer);
}

Future<void> _movePointersToAngle(
  WidgetTester tester,
  TestGesture firstPointer,
  TestGesture secondPointer,
  double angle,
) async {
  const center = Offset(200, 200);
  final radius = 100.0;
  final halfLine = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  await firstPointer.moveTo(center - halfLine);
  await secondPointer.moveTo(center + halfLine);
  await tester.pump();
}

double _visualRotation(WidgetTester tester) {
  final transforms = tester
      .widgetList<Transform>(
        find.descendant(
          of: find.byType(CustomPhotoViewer),
          matching: find.byType(Transform),
        ),
      )
      .toList();
  final rotationTransform = transforms[1];
  return math.atan2(
    rotationTransform.transform.storage[1],
    rotationTransform.transform.storage[0],
  );
}
