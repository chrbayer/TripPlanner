import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model/trip.dart';
import 'model/vehicle.dart';
import 'planner/demo_route.dart';
import 'planner/optimizer.dart';
import 'services/route_service.dart';
import 'services/superchargers.dart';

enum RouteMode { real, demo }

class DemoParams {
  final double lengthKm;
  final double spacingKm;
  final double chargerKw;
  const DemoParams({
    this.lengthKm = 600,
    this.spacingKm = 50,
    this.chargerKw = 250,
  });
}

class AppState extends ChangeNotifier {
  Vehicle vehicle = modelYStandardLfp;
  TripConditions conditions = const TripConditions();
  String from = 'München';
  String to = 'Hamburg';
  RouteMode mode = RouteMode.real;
  DemoParams demo = const DemoParams();
  double maxChargerOffsetKm = 5;

  bool busy = false;
  String? status;
  String? error;
  TripRoute? route;
  OptimizationResult? result;

  final SuperchargerRepository _superchargers;

  AppState({SuperchargerRepository? superchargers})
    : _superchargers = superchargers ?? SuperchargerRepository();
  String? _routeKey;
  SharedPreferences? _prefs;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    try {
      // Only a profile the user edited is stored; otherwise the built-in
      // preset applies, so preset updates reach existing installs.
      final v = p.getString('customVehicle');
      if (v != null) vehicle = Vehicle.fromJson(jsonDecode(v));
      final c = p.getString('conditions');
      if (c != null) conditions = TripConditions.fromJson(jsonDecode(c));
    } catch (_) {
      // Ignore incompatible stored settings.
    }
    from = p.getString('from') ?? from;
    to = p.getString('to') ?? to;
    maxChargerOffsetKm =
        p.getDouble('maxChargerOffsetKm') ?? maxChargerOffsetKm;
    notifyListeners();
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setString('conditions', jsonEncode(conditions.toJson()));
    p.setString('from', from);
    p.setString('to', to);
    p.setDouble('maxChargerOffsetKm', maxChargerOffsetKm);
  }

  void update(void Function() change) {
    change();
    _save();
    notifyListeners();
  }

  void setVehicle(Vehicle v) {
    update(() => vehicle = v);
    final p = _prefs;
    if (p == null) return;
    p.remove('vehicle');
    if (identical(v, modelYStandardLfp)) {
      p.remove('customVehicle');
    } else {
      p.setString('customVehicle', jsonEncode(v.toJson()));
    }
  }

  Future<void> plan() async {
    if (busy) return;
    busy = true;
    error = null;
    status = 'Starte …';
    notifyListeners();
    try {
      final TripRoute r;
      if (mode == RouteMode.demo) {
        r = demoRoute(
          lengthKm: demo.lengthKm,
          chargerSpacingKm: demo.spacingKm,
          chargerKw: demo.chargerKw,
        );
      } else {
        final key = '$from|$to|$maxChargerOffsetKm';
        if (_routeKey == key && route != null && route!.geometry.isNotEmpty) {
          r = route!;
        } else {
          final svc = RouteService(
            _superchargers,
            onStatus: (s) {
              status = s;
              notifyListeners();
            },
          );
          r = await svc.build(from, to, maxChargerOffsetKm: maxChargerOffsetKm);
          _routeKey = key;
        }
      }
      route = r;
      status =
          'Optimiere Geschwindigkeit und Ladestopps '
          '(${r.chargers.length} Lader) …';
      notifyListeners();
      result = await _optimizeInBackground(vehicle, conditions, r);
      if (result!.best == null) {
        error =
            'Keine machbare Planung gefunden – Start-Ladestand erhöhen, '
            'Mindest-Ladestände senken oder den Umweg zu Ladern vergrößern.';
      }
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      status = null;
      notifyListeners();
    }
  }
}

/// Top-level so the isolate closure captures only its arguments, not the
/// (unsendable) [AppState].
Future<OptimizationResult> _optimizeInBackground(
  Vehicle v,
  TripConditions c,
  TripRoute r,
) => Isolate.run(() => optimizeTrip(v, c, r));
