import 'dart:math' as math;
import 'dart:typed_data';

import '../model/physics.dart';
import '../model/trip.dart';
import '../model/vehicle.dart';

/// Driving between two nodes (start, charger, destination) at one cruise speed.
class PlanLeg {
  final String from;
  final String to;
  final double startKm;
  final double endKm;
  final double cruiseKmh;
  final double hours;
  final double kwh;
  final double departureSoc;
  final double arrivalSoc;

  const PlanLeg({
    required this.from,
    required this.to,
    required this.startKm,
    required this.endKm,
    required this.cruiseKmh,
    required this.hours,
    required this.kwh,
    required this.departureSoc,
    required this.arrivalSoc,
  });

  double get distanceKm => endKm - startKm;
  double get avgKmh => distanceKm / hours;
  double get kwhPer100km => kwh / distanceKm * 100;
}

class PlanStop {
  final ChargerSite charger;
  final double arrivalSoc;
  final double departureSoc;
  final double chargeHours;

  /// Detour and fixed stop overhead.
  final double overheadHours;
  final double kwhCharged;

  const PlanStop({
    required this.charger,
    required this.arrivalSoc,
    required this.departureSoc,
    required this.chargeHours,
    required this.overheadHours,
    required this.kwhCharged,
  });

  double get avgKw => kwhCharged / chargeHours;
}

class TripPlan {
  final List<PlanLeg> legs;
  final List<PlanStop> stops;

  /// State of charge along the route: (km, soc %).
  final List<({double km, double soc})> socTrace;

  const TripPlan({
    required this.legs,
    required this.stops,
    required this.socTrace,
  });

  double get driveHours => legs.fold(0.0, (s, l) => s + l.hours);
  double get chargeHours => stops.fold(0.0, (s, c) => s + c.chargeHours);
  double get overheadHours => stops.fold(0.0, (s, c) => s + c.overheadHours);
  double get totalHours => driveHours + chargeHours + overheadHours;
  double get energyKwh => legs.fold(0.0, (s, l) => s + l.kwh);
  double get distanceKm => legs.isEmpty ? 0 : legs.last.endKm;
  double get arrivalSoc => legs.isEmpty ? 0 : legs.last.arrivalSoc;
}

class OptimizationResult {
  /// Fastest plan with a free choice of cruise speed per leg.
  final TripPlan? best;

  /// Fastest plan when driving one constant cruise speed for the whole trip.
  final List<({double kmh, TripPlan? plan})> constantSpeed;

  const OptimizationResult({required this.best, required this.constantSpeed});
}

/// Finds the fastest combination of cruise speeds, charging stops and
/// charge amounts.
///
/// Dynamic programming over (node, arrival SoC in 1 % steps). A node is the
/// start, a charger or the destination. Between two nodes one cruise speed
/// is driven; at a charger the car charges from its arrival SoC to any
/// higher SoC along the charging curve.
OptimizationResult optimizeTrip(
  Vehicle vehicle,
  TripConditions cond,
  TripRoute route,
) {
  final speeds = <double>[];
  for (var v = cond.minCruiseKmh; v <= cond.maxCruiseKmh + 1e-9; v += 5) {
    speeds.add(v);
  }
  final planner = _Planner(vehicle, cond, route, speeds);
  return OptimizationResult(
    best: planner.solve(List.generate(speeds.length, (i) => i)),
    constantSpeed: [
      for (var k = 0; k < speeds.length; k++)
        (kmh: speeds[k], plan: planner.solve([k])),
    ],
  );
}

class _Node {
  final String name;
  final int boundary;
  final ChargerSite? charger;
  _Node(this.name, this.boundary, this.charger);
}

class _Planner {
  final Vehicle vehicle;
  final TripConditions cond;
  final TripRoute route;
  final List<double> speeds;
  final DrivingModel model;

  late final List<_Node> nodes;
  late final Float64List cumM;

  /// Per speed: cumulative energy (kWh) and time (h) at segment boundaries.
  late final List<Float64List> cumKwh;
  late final List<Float64List> cumH;

  /// Per speed and node n ≥ 1: max of cumKwh over boundaries in
  /// (boundary[n-1], boundary[n]] – for the lowest SoC while driving.
  late final List<Float64List> peakKwh;

  /// Per charger power: hours to charge from 0 % to i % (i = 0..100).
  final Map<double, Float64List> _chargeCum = {};

  static const _levels = 101;

  _Planner(this.vehicle, this.cond, this.route, this.speeds)
    : model = DrivingModel(vehicle, cond) {
    final segs = route.segments;
    cumM = Float64List(segs.length + 1);
    for (var i = 0; i < segs.length; i++) {
      cumM[i + 1] = cumM[i] + segs[i].lengthM;
    }
    cumKwh = [];
    cumH = [];
    for (final v in speeds) {
      final e = Float64List(segs.length + 1);
      final t = Float64List(segs.length + 1);
      for (var i = 0; i < segs.length; i++) {
        final r = model.segment(segs[i], v);
        e[i + 1] = e[i] + r.kwh;
        t[i + 1] = t[i] + r.hours;
      }
      cumKwh.add(e);
      cumH.add(t);
    }

    final chargers = [...route.chargers]
      ..sort((a, b) => a.routePosM.compareTo(b.routePosM));
    nodes = [
      _Node(route.startName, 0, null),
      for (final c in chargers)
        if (c.routePosM > 0 && c.routePosM < cumM.last)
          _Node(c.name, _boundaryAt(c.routePosM), c),
      _Node(route.destinationName, segs.length, null),
    ];

    peakKwh = [
      for (final e in cumKwh)
        Float64List(nodes.length)..setAll(0, [
          0.0,
          for (var n = 1; n < nodes.length; n++)
            _maxRange(e, nodes[n - 1].boundary + 1, nodes[n].boundary),
        ]),
    ];
  }

  int _boundaryAt(double posM) {
    var lo = 0, hi = cumM.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (cumM[mid] <= posM) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (posM - cumM[lo] < cumM[hi] - posM) ? lo : hi;
  }

  static double _maxRange(Float64List a, int from, int to) {
    var m = double.negativeInfinity;
    for (var i = from; i <= to; i++) {
      m = math.max(m, a[i]);
    }
    return m;
  }

  Float64List _chargeTable(double chargerKw) =>
      _chargeCum.putIfAbsent(chargerKw, () {
        final t = Float64List(_levels);
        for (var i = 1; i < _levels; i++) {
          t[i] = t[i - 1] + model.chargeHours(i - 1.0, i.toDouble(), chargerKw);
        }
        return t;
      });

  double _detourKwh(ChargerSite c) =>
      c.detourM / 1000 * model.consumptionKwhPer100km(50) / 100;

  double _overheadHours(ChargerSite c) =>
      cond.stopOverheadMin / 60 + c.detourM / 1000 / 50;

  /// Solves for the fastest plan using only the speed indices [allowed].
  TripPlan? solve(List<int> allowed) {
    final n = nodes.length;
    final cap = vehicle.usableKwh;
    final hardFloor = math.min(
      3.0,
      math.min(cond.minArrivalSocCharger, cond.minArrivalSocDestination),
    );
    final maxIdx = cond.maxChargeSoc.floor().clamp(0, 100);
    final startIdx = cond.startSoc.round().clamp(0, 100);

    final best = List.generate(
      n,
      (_) => Float64List(_levels)..fillRange(0, _levels, double.infinity),
    );
    // Parent of an arrival state: previous node, departure SoC, speed index.
    final parNode = List.generate(
      n,
      (_) => Int16List(_levels)..fillRange(0, _levels, -1),
    );
    final parDep = List.generate(n, (_) => Int16List(_levels));
    final parSpeed = List.generate(n, (_) => Int16List(_levels));
    // For a departure SoC at a node: the arrival SoC it was charged from.
    final depFrom = List.generate(n, (_) => Int16List(_levels));

    best[0][startIdx] = 0;
    final dep = Float64List(_levels);

    for (var i = 0; i < n - 1; i++) {
      dep.fillRange(0, _levels, double.infinity);
      final node = nodes[i];
      if (i == 0) {
        dep[startIdx] = 0;
        depFrom[0][startIdx] = startIdx;
      } else {
        // dep[d] = min_{a<d} best[a] + T(a→d) + overhead
        //        = cum[d] + overhead + min_{a<d} (best[a] - cum[a])
        final c = node.charger!;
        final cum = _chargeTable(math.min(c.maxKw, vehicle.maxDcKw));
        final overhead = _overheadHours(c);
        var runMin = double.infinity;
        var runArg = -1;
        for (var d = 0; d <= maxIdx; d++) {
          if (runArg >= 0) {
            dep[d] = runMin + cum[d] + overhead;
            depFrom[i][d] = runArg;
          }
          final v = best[i][d] - cum[d];
          if (v < runMin) {
            runMin = v;
            runArg = d;
          }
        }
      }

      for (var d = 0; d < _levels; d++) {
        final t0 = dep[d];
        if (t0 == double.infinity) continue;
        for (final k in allowed) {
          final e = cumKwh[k], t = cumH[k], peak = peakKwh[k];
          final e0 = e[node.boundary];
          final t1 = t[node.boundary];
          var runPeak = e0;
          for (var j = i + 1; j < n; j++) {
            runPeak = math.max(runPeak, peak[j]);
            if (d - (runPeak - e0) / cap * 100 < hardFloor) break;
            final target = nodes[j];
            final isDest = j == n - 1;
            var need = e[target.boundary] - e0;
            if (!isDest) need += _detourKwh(target.charger!);
            final arr = d - need / cap * 100;
            final minArr = isDest
                ? cond.minArrivalSocDestination
                : cond.minArrivalSocCharger;
            if (arr < minArr) continue;
            final a = math.min(arr.floor(), 100);
            final time = t0 + t[target.boundary] - t1;
            if (time < best[j][a]) {
              best[j][a] = time;
              parNode[j][a] = i;
              parDep[j][a] = d;
              parSpeed[j][a] = k;
            }
          }
        }
      }
    }

    // Best arrival at the destination.
    var bestA = -1;
    for (var a = 0; a < _levels; a++) {
      if (best[n - 1][a] < double.infinity &&
          (bestA < 0 || best[n - 1][a] < best[n - 1][bestA] - 1e-9)) {
        bestA = a;
      }
    }
    if (bestA < 0) return null;

    // Walk back: collect (node, arrival SoC idx, dep idx at prev, speed).
    final hops = <({int from, int to, int dep, int k})>[];
    var j = n - 1, a = bestA;
    while (j != 0) {
      final i = parNode[j][a];
      final d = parDep[j][a];
      hops.add((from: i, to: j, dep: d, k: parSpeed[j][a]));
      j = i;
      a = depFrom[i][d];
    }
    return _buildPlan(hops.reversed.toList());
  }

  TripPlan _buildPlan(List<({int from, int to, int dep, int k})> hops) {
    final cap = vehicle.usableKwh;
    final legs = <PlanLeg>[];
    final stops = <PlanStop>[];
    final trace = <({double km, double soc})>[];

    var soc = cond.startSoc.roundToDouble().clamp(0.0, 100.0);
    for (final h in hops) {
      final from = nodes[h.from], to = nodes[h.to];
      if (from.charger != null) {
        final c = from.charger!;
        final dep = h.dep.toDouble();
        final kw = math.min(c.maxKw, vehicle.maxDcKw);
        stops.add(
          PlanStop(
            charger: c,
            arrivalSoc: soc,
            departureSoc: dep,
            chargeHours: model.chargeHours(soc, dep, kw),
            overheadHours: _overheadHours(c),
            kwhCharged: (dep - soc) / 100 * cap,
          ),
        );
        soc = dep;
      }
      final depSoc = soc;
      final e = cumKwh[h.k], t = cumH[h.k];
      final step = math.max(1, (to.boundary - from.boundary) ~/ 200);
      for (var b = from.boundary; b <= to.boundary; b += step) {
        trace.add((
          km: cumM[b] / 1000,
          soc: depSoc - (e[b] - e[from.boundary]) / cap * 100,
        ));
      }
      var kwh = e[to.boundary] - e[from.boundary];
      if (to.charger != null) kwh += _detourKwh(to.charger!);
      soc = depSoc - kwh / cap * 100;
      trace.add((km: cumM[to.boundary] / 1000, soc: soc));
      legs.add(
        PlanLeg(
          from: from.name,
          to: to.name,
          startKm: cumM[from.boundary] / 1000,
          endKm: cumM[to.boundary] / 1000,
          cruiseKmh: speeds[h.k],
          hours: t[to.boundary] - t[from.boundary],
          kwh: kwh,
          departureSoc: depSoc,
          arrivalSoc: soc,
        ),
      );
    }
    return TripPlan(legs: legs, stops: stops, socTrace: trace);
  }
}
