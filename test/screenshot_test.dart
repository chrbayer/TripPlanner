// Renders the app to PNGs for visual checks.
// Run with: flutter test test/screenshot_test.dart --dart-define=OUT=<dir>
// Add --dart-define=ONLINE=true to plan a real route (München → Hamburg).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/app_state.dart';
import 'package:trip_planner/main.dart';
import 'package:trip_planner/model/trip.dart';
import 'package:trip_planner/planner/demo_route.dart';
import 'package:trip_planner/planner/optimizer.dart';
import 'package:trip_planner/services/superchargers.dart';
import 'package:trip_planner/ui/vehicle_page.dart';

Future<void> _font(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    final b = File(f).readAsBytesSync();
    l.addFont(Future.value(ByteData.sublistView(b)));
  }
  await l.load();
}

void main() {
  const out = String.fromEnvironment('OUT');
  testWidgets('screenshot', (tester) async {
    final fonts =
        '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts';
    await tester.runAsync(() async {
      await _font('Roboto', [
        '$fonts/Roboto-Regular.ttf',
        '$fonts/Roboto-Medium.ttf',
        '$fonts/Roboto-Bold.ttf',
      ]);
      await _font('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    });
    final state = AppState()..mode = RouteMode.demo;
    final route = demoRoute(lengthKm: 600);
    state.route = route;
    state.result = optimizeTrip(state.vehicle, const TripConditions(), route);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
    if (const bool.fromEnvironment('ONLINE')) {
      HttpOverrides.global = null;
      final real = AppState(
        superchargers: SuperchargerRepository(
          cacheDir: Directory('${Directory.systemTemp.path}/trip_planner_test'),
        ),
      );
      await tester.runAsync(() => real.plan());
      expect(real.error, isNull);
      state
        ..route = real.route
        ..result = real.result
        ..mode = RouteMode.real;
    }
    for (final (name, w, h, page) in [
      ('home_wide', 1400.0, 2400.0, 0),
      ('home_phone', 412.0, 900.0, 0),
      ('result_phone', 412.0, 1400.0, 2),
      ('vehicle', 1400.0, 1000.0, 1),
    ]) {
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF2A78D6),
              ),
            ),
            home: page == 1
                ? VehiclePage(state: state)
                : HomePage(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (page == 2) {
        await tester.tap(find.text('Ergebnis'));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final img =
            await (key.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  }, skip: out.isEmpty);
}
