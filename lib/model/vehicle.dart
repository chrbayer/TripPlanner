import 'dart:math' as math;

/// A point on the DC charging curve: battery state of charge (0..100 %)
/// and the maximum charging power the car accepts at that SoC.
class CurvePoint {
  final double soc;
  final double kw;
  const CurvePoint(this.soc, this.kw);

  Map<String, dynamic> toJson() => {'soc': soc, 'kw': kw};
  factory CurvePoint.fromJson(Map<String, dynamic> j) =>
      CurvePoint((j['soc'] as num).toDouble(), (j['kw'] as num).toDouble());
}

/// Physical and electrical parameters of an electric vehicle.
class Vehicle {
  final String name;

  /// Usable (net) battery capacity in kWh.
  final double usableKwh;

  /// Curb weight incl. driver in kg (payload is added per trip).
  final double massKg;

  /// Aerodynamic drag coefficient.
  final double cd;

  /// Frontal area in m².
  final double frontalAreaM2;

  /// Rolling resistance coefficient.
  final double crr;

  /// Battery → wheel efficiency when driving (inverter, motor, gearbox).
  final double drivetrainEff;

  /// Wheel → battery efficiency when recuperating.
  final double regenEff;

  /// Maximum recuperation power at the wheel in kW.
  final double maxRegenKw;

  /// Constant auxiliary load (electronics, computer, lights) in kW.
  final double auxKw;

  /// Heating demand per Kelvin below [comfortTempC] in kW/K (heat pump).
  final double heatingKwPerK;

  /// Cooling demand per Kelvin above [comfortTempC] + 6 K in kW/K.
  final double coolingKwPerK;

  final double comfortTempC;

  /// Maximum DC charging power of the car in kW.
  final double maxDcKw;

  /// DC charging curve (battery side), sorted by SoC.
  final List<CurvePoint> chargeCurve;

  const Vehicle({
    required this.name,
    required this.usableKwh,
    required this.massKg,
    required this.cd,
    required this.frontalAreaM2,
    required this.crr,
    required this.drivetrainEff,
    required this.regenEff,
    required this.maxRegenKw,
    required this.auxKw,
    required this.heatingKwPerK,
    required this.coolingKwPerK,
    required this.comfortTempC,
    required this.maxDcKw,
    required this.chargeCurve,
  });

  /// Charging power the car accepts at [socPct] (0..100), capped by [maxDcKw].
  double chargePowerAt(double socPct) {
    final c = chargeCurve;
    if (socPct <= c.first.soc) return math.min(c.first.kw, maxDcKw);
    if (socPct >= c.last.soc) return math.min(c.last.kw, maxDcKw);
    for (var i = 1; i < c.length; i++) {
      if (socPct <= c[i].soc) {
        final a = c[i - 1], b = c[i];
        final t = (socPct - a.soc) / (b.soc - a.soc);
        return math.min(a.kw + t * (b.kw - a.kw), maxDcKw);
      }
    }
    return math.min(c.last.kw, maxDcKw);
  }

  /// HVAC load in kW for the given outside temperature.
  double hvacKw(double outsideTempC) {
    if (outsideTempC < comfortTempC) {
      return (comfortTempC - outsideTempC) * heatingKwPerK;
    }
    if (outsideTempC > comfortTempC + 6) {
      return (outsideTempC - comfortTempC - 6) * coolingKwPerK;
    }
    return 0;
  }

  Vehicle copyWith({
    String? name,
    double? usableKwh,
    double? massKg,
    double? cd,
    double? frontalAreaM2,
    double? crr,
    double? drivetrainEff,
    double? regenEff,
    double? maxRegenKw,
    double? auxKw,
    double? heatingKwPerK,
    double? coolingKwPerK,
    double? comfortTempC,
    double? maxDcKw,
    List<CurvePoint>? chargeCurve,
  }) => Vehicle(
    name: name ?? this.name,
    usableKwh: usableKwh ?? this.usableKwh,
    massKg: massKg ?? this.massKg,
    cd: cd ?? this.cd,
    frontalAreaM2: frontalAreaM2 ?? this.frontalAreaM2,
    crr: crr ?? this.crr,
    drivetrainEff: drivetrainEff ?? this.drivetrainEff,
    regenEff: regenEff ?? this.regenEff,
    maxRegenKw: maxRegenKw ?? this.maxRegenKw,
    auxKw: auxKw ?? this.auxKw,
    heatingKwPerK: heatingKwPerK ?? this.heatingKwPerK,
    coolingKwPerK: coolingKwPerK ?? this.coolingKwPerK,
    comfortTempC: comfortTempC ?? this.comfortTempC,
    maxDcKw: maxDcKw ?? this.maxDcKw,
    chargeCurve: chargeCurve ?? this.chargeCurve,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'usableKwh': usableKwh,
    'massKg': massKg,
    'cd': cd,
    'frontalAreaM2': frontalAreaM2,
    'crr': crr,
    'drivetrainEff': drivetrainEff,
    'regenEff': regenEff,
    'maxRegenKw': maxRegenKw,
    'auxKw': auxKw,
    'heatingKwPerK': heatingKwPerK,
    'coolingKwPerK': coolingKwPerK,
    'comfortTempC': comfortTempC,
    'maxDcKw': maxDcKw,
    'chargeCurve': chargeCurve.map((p) => p.toJson()).toList(),
  };

  factory Vehicle.fromJson(Map<String, dynamic> j) {
    double d(String k) => (j[k] as num).toDouble();
    return Vehicle(
      name: j['name'] as String,
      usableKwh: d('usableKwh'),
      massKg: d('massKg'),
      cd: d('cd'),
      frontalAreaM2: d('frontalAreaM2'),
      crr: d('crr'),
      drivetrainEff: d('drivetrainEff'),
      regenEff: d('regenEff'),
      maxRegenKw: d('maxRegenKw'),
      auxKw: d('auxKw'),
      heatingKwPerK: d('heatingKwPerK'),
      coolingKwPerK: d('coolingKwPerK'),
      comfortTempC: d('comfortTempC'),
      maxDcKw: d('maxDcKw'),
      chargeCurve: (j['chargeCurve'] as List)
          .map((e) => CurvePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Tesla Model Y Standard RWD (2026, "Juniper"-Plattform) mit CATL-LFP-Akku.
///
/// Quellen / Annahmen:
/// - Akku 64,0 kWh brutto / 60,5 kWh netto (evkx.net, electrive.net)
/// - DC max. 175 kW, 10–80 % in ca. 25–30 min (Ø 85–100 kW)
/// - Leergewicht 1906 kg (evspecifications.com) + 75 kg Fahrer
/// - cW 0,23 × A 2,57 m² → ~20 kWh/100 km bei 130 km/h (electrive-Test:
///   "Autobahn 120–130 km/h kaum über 20 kWh/100 km")
/// - Ladekurve: evkx.net "Tesla Model Y Standard 64 kWh" (Diagramm-SVG,
///   1-%-Raster, vereinfacht auf max. 0,5 kW Abweichung): 173 kW bei 4–5 %,
///   Abfall ab ~13 %, ~89 kW bei 50 %, ~46 kW bei 80 % → 10→80 % ≈ 29 min.
const modelYStandardLfp = Vehicle(
  name: 'Tesla Model Y Standard RWD 2026 (CATL LFP 60,5 kWh)',
  usableKwh: 60.5,
  massKg: 1981,
  cd: 0.23,
  frontalAreaM2: 2.57,
  crr: 0.0085,
  drivetrainEff: 0.88,
  regenEff: 0.70,
  maxRegenKw: 60,
  auxKw: 0.3,
  heatingKwPerK: 0.06,
  coolingKwPerK: 0.08,
  comfortTempC: 18,
  maxDcKw: 175,
  chargeCurve: [
    CurvePoint(0, 120),
    CurvePoint(4, 173),
    CurvePoint(10, 170),
    CurvePoint(11, 169),
    CurvePoint(12, 169),
    CurvePoint(13, 167),
    CurvePoint(14, 162),
    CurvePoint(15, 155),
    CurvePoint(16, 147),
    CurvePoint(17, 143),
    CurvePoint(18, 142),
    CurvePoint(19, 138),
    CurvePoint(20, 136),
    CurvePoint(21, 135),
    CurvePoint(22, 133),
    CurvePoint(24, 131),
    CurvePoint(25, 129),
    CurvePoint(27, 129),
    CurvePoint(32, 124),
    CurvePoint(38, 113),
    CurvePoint(40, 107),
    CurvePoint(45, 96),
    CurvePoint(52, 86),
    CurvePoint(55, 83),
    CurvePoint(57, 79),
    CurvePoint(60, 75),
    CurvePoint(61, 73),
    CurvePoint(63, 71),
    CurvePoint(65, 67),
    CurvePoint(67, 65),
    CurvePoint(71, 58),
    CurvePoint(74, 55),
    CurvePoint(79, 47),
    CurvePoint(83, 43),
    CurvePoint(84, 41),
    CurvePoint(87, 38),
    CurvePoint(88, 38),
    CurvePoint(91, 35),
    CurvePoint(92, 33),
    CurvePoint(93, 33),
    CurvePoint(97, 25),
    CurvePoint(99, 18),
    CurvePoint(100, 12),
  ],
);

const vehiclePresets = [modelYStandardLfp];
