import 'dart:math' as math;

import 'trip.dart';
import 'vehicle.dart';

const _g = 9.81;

/// Air density in kg/m³ at sea level for the given temperature.
double airDensity(double tempC) => 101325 / (287.05 * (tempC + 273.15));

/// Energy and time model for driving a vehicle under given conditions.
class DrivingModel {
  final Vehicle vehicle;
  final TripConditions conditions;

  late final double _massKg = vehicle.massKg + conditions.payloadKg;
  late final double _rho = airDensity(conditions.outsideTempC);
  late final double _auxKw =
      vehicle.auxKw + vehicle.hvacKw(conditions.outsideTempC);

  DrivingModel(this.vehicle, this.conditions);

  /// Speed actually driven on [seg] when the driver's cruise target is
  /// [targetKmh], in km/h.
  double effectiveSpeedKmh(RouteSegment seg, double targetKmh) {
    if (seg.isFastRoad) {
      final limit = conditions.speedLimitKmh;
      return limit == null ? targetKmh : math.min(targetKmh, limit);
    }
    return math.min(seg.roadSpeedKmh, targetKmh);
  }

  /// Battery power in kW at constant speed [vKmh] on a slope of [grade]
  /// (rise/run).
  double batteryPowerKw(double vKmh, {double grade = 0}) {
    final v = vKmh / 3.6;
    final vAir = v + conditions.headwindKmh / 3.6;
    final theta = math.atan(grade);
    final fAero =
        0.5 * _rho * vehicle.cd * vehicle.frontalAreaM2 * vAir * vAir.abs();
    final fRoll = vehicle.crr * _massKg * _g * math.cos(theta);
    final fSlope = _massKg * _g * math.sin(theta);
    final wheelKw = (fAero + fRoll + fSlope) * v / 1000;
    final double driveKw;
    if (wheelKw >= 0) {
      driveKw = wheelKw / vehicle.drivetrainEff;
    } else {
      // Recuperation is limited; the rest goes into the friction brakes.
      driveKw = math.max(wheelKw, -vehicle.maxRegenKw) * vehicle.regenEff;
    }
    return driveKw + _auxKw;
  }

  /// Consumption in kWh/100 km on flat road at [vKmh].
  double consumptionKwhPer100km(double vKmh) =>
      batteryPowerKw(vKmh) / vKmh * 100;

  /// Energy (kWh) and time (h) to drive [seg] with cruise target [targetKmh].
  ({double kwh, double hours}) segment(RouteSegment seg, double targetKmh) {
    final v = effectiveSpeedKmh(seg, targetKmh);
    final hours = seg.lengthM / 1000 / v;
    final grade = seg.lengthM > 0 ? seg.climbM / seg.lengthM : 0.0;
    return (kwh: batteryPowerKw(v, grade: grade) * hours, hours: hours);
  }

  /// Time in hours to charge from [fromSoc] to [toSoc] (percent) at a
  /// charger limited to [chargerKw].
  double chargeHours(double fromSoc, double toSoc, double chargerKw) {
    if (toSoc <= fromSoc) return 0;
    const step = 0.25;
    final kwhPerStep = vehicle.usableKwh * step / 100;
    var hours = 0.0;
    for (var s = fromSoc; s < toSoc - 1e-9; s += step) {
      final ds = math.min(step, toSoc - s);
      final p = math.min(vehicle.chargePowerAt(s + ds / 2), chargerKw);
      hours += kwhPerStep * (ds / step) / p;
    }
    return hours;
  }
}
