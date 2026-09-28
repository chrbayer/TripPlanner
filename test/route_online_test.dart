// Online end-to-end check against the public services.
// Run with: flutter test test/route_online_test.dart --dart-define=ONLINE=true
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/model/trip.dart';
import 'package:trip_planner/model/vehicle.dart';
import 'package:trip_planner/planner/optimizer.dart';
import 'package:trip_planner/services/route_service.dart';
import 'package:trip_planner/services/superchargers.dart';

void main() {
  const online = bool.fromEnvironment('ONLINE');
  test(
    'München → Hamburg',
    () async {
      final dir = Directory('${Directory.systemTemp.path}/trip_planner_test')
        ..createSync(recursive: true);
      final svc = RouteService(
        SuperchargerRepository(cacheDir: dir),
        // ignore: avoid_print
        onStatus: print,
      );
      final route = await svc.build('München', 'Hamburg');
      final climb = route.segments.fold(
        0.0,
        (s, e) => s + (e.climbM > 0 ? e.climbM : 0),
      );
      // ignore: avoid_print
      print(
        '${route.startName} → ${route.destinationName}: '
        '${(route.lengthM / 1000).round()} km, ${route.segments.length} Segmente, '
        '${climb.round()} Hm, ${route.chargers.length} Supercharger',
      );
      final sw = Stopwatch()..start();
      final r = optimizeTrip(modelYStandardLfp, const TripConditions(), route);
      final best = r.best!;
      // ignore: avoid_print
      print(
        'Optimierung ${sw.elapsedMilliseconds} ms; '
        '${(best.totalHours * 60).round()} min, ${best.stops.length} Stopps',
      );
      for (final l in best.legs) {
        // ignore: avoid_print
        print(
          '  ${l.cruiseKmh.round()} km/h  ${l.distanceKm.round()} km  '
          '${l.departureSoc.round()}→${l.arrivalSoc.round()} %  → ${l.to}',
        );
      }
      for (final s in best.stops) {
        // ignore: avoid_print
        print(
          '  ${s.charger.name}: ${s.arrivalSoc.round()}→${s.departureSoc.round()} % '
          '${(s.chargeHours * 60).round()} min',
        );
      }
      expect(best.legs.last.arrivalSoc, greaterThanOrEqualTo(15));
    },
    skip: !online,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
