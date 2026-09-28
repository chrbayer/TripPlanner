import 'package:flutter_test/flutter_test.dart';
import 'package:trip_planner/model/physics.dart';
import 'package:trip_planner/model/trip.dart';
import 'package:trip_planner/model/vehicle.dart';
import 'package:trip_planner/planner/demo_route.dart';
import 'package:trip_planner/planner/optimizer.dart';

void main() {
  const car = modelYStandardLfp;
  final model = DrivingModel(car, const TripConditions(outsideTempC: 15));

  test('Verbrauch Model Y Standard im plausiblen Bereich', () {
    final c100 = model.consumptionKwhPer100km(100);
    final c130 = model.consumptionKwhPer100km(130);
    final c160 = model.consumptionKwhPer100km(160);
    // ignore: avoid_print
    print(
      '100: ${c100.toStringAsFixed(1)}  130: ${c130.toStringAsFixed(1)}  '
      '160: ${c160.toStringAsFixed(1)} kWh/100km',
    );
    expect(c100, inInclusiveRange(13, 16.5));
    expect(c130, inInclusiveRange(18.5, 22));
    expect(c160, greaterThan(c130 * 1.3));
  });

  test('Ladezeit 10→80 % etwa 25–30 min', () {
    final min = model.chargeHours(10, 80, 250) * 60;
    // ignore: avoid_print
    print('10→80 %: ${min.toStringAsFixed(1)} min');
    expect(min, inInclusiveRange(24, 30));
    // Slow charger takes longer.
    expect(model.chargeHours(10, 80, 50) * 60, greaterThan(min * 1.5));
  });

  test('Kurze Strecke ohne Laden', () {
    final r = optimizeTrip(
      car,
      const TripConditions(startSoc: 90),
      demoRoute(lengthKm: 150),
    );
    expect(r.best, isNotNull);
    expect(r.best!.stops, isEmpty);
    expect(r.best!.arrivalSoc, greaterThanOrEqualTo(15));
  });

  test('600 km: Optimum schlägt Vollgas und Schleichen', () {
    const cond = TripConditions(startSoc: 90);
    final r = optimizeTrip(car, cond, demoRoute(lengthKm: 600));
    final best = r.best!;
    for (final l in best.legs) {
      expect(l.arrivalSoc, greaterThanOrEqualTo(8 - 1e-6));
    }
    final fastest = r.constantSpeed.last.plan!;
    final slow = r.constantSpeed.first.plan!;
    // ignore: avoid_print
    print(
      'best ${(best.totalHours * 60).round()} min, '
      '${best.stops.length} Stopps, speeds '
      '${best.legs.map((l) => l.cruiseKmh.round()).toList()}; '
      'max: ${(fastest.totalHours * 60).round()} min, '
      'min: ${(slow.totalHours * 60).round()} min',
    );
    for (final c in r.constantSpeed) {
      if (c.plan != null) {
        // ignore: avoid_print
        print(
          '  ${c.kmh.round()} km/h → ${(c.plan!.totalHours * 60).round()} min, '
          '${c.plan!.stops.length} Stopps',
        );
      }
    }
    expect(best.totalHours, lessThanOrEqualTo(fastest.totalHours));
    expect(best.totalHours, lessThan(slow.totalHours));
    expect(best.stops, isNotEmpty);
    // SoC bookkeeping is consistent.
    for (var i = 0; i < best.stops.length; i++) {
      expect(best.stops[i].departureSoc, best.legs[i + 1].departureSoc);
      expect(best.stops[i].arrivalSoc, closeTo(best.legs[i].arrivalSoc, 1e-9));
    }
  });

  test('Unerreichbar ohne Lader', () {
    final r = optimizeTrip(
      car,
      const TripConditions(startSoc: 50),
      demoRoute(lengthKm: 600, chargerSpacingKm: 1000),
    );
    expect(r.best, isNull);
  });
}
