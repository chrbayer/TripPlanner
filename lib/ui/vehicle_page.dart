import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/physics.dart';
import '../model/trip.dart';
import '../model/vehicle.dart';
import 'format.dart';

class VehiclePage extends StatefulWidget {
  final AppState state;
  const VehiclePage({super.key, required this.state});

  @override
  State<VehiclePage> createState() => _VehiclePageState();
}

typedef _Field = ({
  String label,
  String unit,
  double Function(Vehicle) get,
  Vehicle Function(Vehicle, double) set,
});

final List<_Field> _fields = [
  (
    label: 'Nutzbare Akkukapazität',
    unit: 'kWh',
    get: (v) => v.usableKwh,
    set: (v, x) => v.copyWith(usableKwh: x),
  ),
  (
    label: 'Gewicht inkl. Fahrer',
    unit: 'kg',
    get: (v) => v.massKg,
    set: (v, x) => v.copyWith(massKg: x),
  ),
  (
    label: 'cW-Wert',
    unit: '',
    get: (v) => v.cd,
    set: (v, x) => v.copyWith(cd: x),
  ),
  (
    label: 'Stirnfläche',
    unit: 'm²',
    get: (v) => v.frontalAreaM2,
    set: (v, x) => v.copyWith(frontalAreaM2: x),
  ),
  (
    label: 'Rollwiderstandsbeiwert',
    unit: '',
    get: (v) => v.crr,
    set: (v, x) => v.copyWith(crr: x),
  ),
  (
    label: 'Wirkungsgrad Antrieb (Akku→Rad)',
    unit: '',
    get: (v) => v.drivetrainEff,
    set: (v, x) => v.copyWith(drivetrainEff: x),
  ),
  (
    label: 'Wirkungsgrad Rekuperation',
    unit: '',
    get: (v) => v.regenEff,
    set: (v, x) => v.copyWith(regenEff: x),
  ),
  (
    label: 'Max. Rekuperationsleistung',
    unit: 'kW',
    get: (v) => v.maxRegenKw,
    set: (v, x) => v.copyWith(maxRegenKw: x),
  ),
  (
    label: 'Grundlast Nebenverbraucher',
    unit: 'kW',
    get: (v) => v.auxKw,
    set: (v, x) => v.copyWith(auxKw: x),
  ),
  (
    label: 'Heizen pro K unter Komforttemp.',
    unit: 'kW/K',
    get: (v) => v.heatingKwPerK,
    set: (v, x) => v.copyWith(heatingKwPerK: x),
  ),
  (
    label: 'Kühlen pro K über Komforttemp. + 6',
    unit: 'kW/K',
    get: (v) => v.coolingKwPerK,
    set: (v, x) => v.copyWith(coolingKwPerK: x),
  ),
  (
    label: 'Komforttemperatur',
    unit: '°C',
    get: (v) => v.comfortTempC,
    set: (v, x) => v.copyWith(comfortTempC: x),
  ),
  (
    label: 'Max. DC-Ladeleistung',
    unit: 'kW',
    get: (v) => v.maxDcKw,
    set: (v, x) => v.copyWith(maxDcKw: x),
  ),
];

class _VehiclePageState extends State<VehiclePage> {
  late Vehicle _v = widget.state.vehicle;
  late List<TextEditingController> _ctrls;
  late TextEditingController _curve;
  String? _curveError;

  @override
  void initState() {
    super.initState();
    _resetControllers();
  }

  void _resetControllers() {
    _ctrls = [
      for (final f in _fields) TextEditingController(text: _fmt(f.get(_v))),
    ];
    _curve = TextEditingController(
      text: _v.chargeCurve
          .map((p) => '${_fmt(p.soc)}:${_fmt(p.kw)}')
          .join('  '),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _apply() {
    var v = _v;
    for (var i = 0; i < _fields.length; i++) {
      final x = double.tryParse(_ctrls[i].text.replaceAll(',', '.'));
      if (x == null || (x <= 0 && _fields[i].unit != '°C')) continue;
      v = _fields[i].set(v, x);
    }
    try {
      final pts =
          _curve.text.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).map((e) {
            final p = e.split(':');
            return CurvePoint(double.parse(p[0]), double.parse(p[1]));
          }).toList()..sort((a, b) => a.soc.compareTo(b.soc));
      if (pts.length < 2) throw const FormatException();
      v = v.copyWith(chargeCurve: pts);
      _curveError = null;
    } catch (_) {
      _curveError =
          'Format: "SoC:kW" durch Leerzeichen getrennt, z. B. 0:120 10:170';
    }
    setState(() => _v = v);
    widget.state.setVehicle(v);
  }

  void _reset() {
    setState(() {
      _v = modelYStandardLfp;
      _resetControllers();
    });
    widget.state.setVehicle(_v);
  }

  @override
  Widget build(BuildContext context) {
    final model = DrivingModel(_v, widget.state.conditions);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fahrzeug'),
        actions: [
          TextButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.restore),
            label: const Text('Model Y Standard'),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 1000;
          final physics = wide
              ? const ClampingScrollPhysics()
              : const NeverScrollableScrollPhysics();
          final form = _form(context, physics);
          final charts = _charts(context, model, physics);
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 420, child: form),
                Expanded(child: charts),
              ],
            );
          }
          return ListView(children: [form, charts]);
        },
      ),
    );
  }

  Widget _form(BuildContext context, ScrollPhysics physics) => ListView(
    shrinkWrap: true,
    physics: physics,
    padding: const EdgeInsets.all(16),
    children: [
      Text(_v.name, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      for (var i = 0; i < _fields.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _ctrls[i],
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: _fields[i].label,
              suffixText: _fields[i].unit,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _apply(),
          ),
        ),
      TextField(
        controller: _curve,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: 'Ladekurve (SoC %:kW)',
          border: const OutlineInputBorder(),
          errorText: _curveError,
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _apply,
        icon: const Icon(Icons.check),
        label: const Text('Übernehmen'),
      ),
    ],
  );

  Widget _charts(
    BuildContext context,
    DrivingModel model,
    ScrollPhysics physics,
  ) {
    final c = ChartColors.of(context);
    final t = Theme.of(context).textTheme;
    final style = t.bodySmall;
    FlTitlesData titles(String x, String y, double xi) => FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        axisNameWidget: Text(x, style: style),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: xi,
          getTitlesWidget: (v, m) => _offGrid(v, m)
              ? const SizedBox.shrink()
              : SideTitleWidget(
                  meta: m,
                  child: Text(fmtNum(v), style: style),
                ),
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text(y, style: style),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (v, m) => _offGrid(v, m)
              ? const SizedBox.shrink()
              : SideTitleWidget(
                  meta: m,
                  child: Text(fmtNum(v), style: style),
                ),
        ),
      ),
    );
    final grid = FlGridData(
      getDrawingHorizontalLine: (_) =>
          FlLine(color: c.grid.withValues(alpha: 0.5), strokeWidth: 1),
      getDrawingVerticalLine: (_) =>
          FlLine(color: c.grid.withValues(alpha: 0.5), strokeWidth: 1),
    );

    final curve = [
      for (var s = 0.0; s <= 100; s += 1) FlSpot(s, _v.chargePowerAt(s)),
    ];
    final cons = [
      for (var v = 30.0; v <= 200; v += 5)
        FlSpot(v, model.consumptionKwhPer100km(v)),
    ];
    final range = [
      for (var v = 30.0; v <= 200; v += 5)
        FlSpot(v, _v.usableKwh / model.consumptionKwhPer100km(v) * 100),
    ];
    const flat = RouteSegment(
      lengthM: 1,
      climbM: 0,
      roadSpeedKmh: 120,
      lat: 0,
      lon: 0,
    );
    final t1080 = model.chargeHours(10, 80, _v.maxDcKw) * 60;
    final c130 = model.segment(flat, 130).kwh * 1000 * 100;

    Widget card(String title, String sub, Widget chart) => Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleMedium),
            Text(sub, style: t.bodySmall),
            const SizedBox(height: 12),
            SizedBox(height: 220, child: chart),
          ],
        ),
      ),
    );
    LineChartBarData bar(List<FlSpot> s, Color col) => LineChartBarData(
      spots: s,
      color: col,
      barWidth: 2,
      dotData: const FlDotData(show: false),
    );

    return ListView(
      shrinkWrap: true,
      physics: physics,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        card(
          'Ladekurve',
          '10 → 80 % an einer ausreichend starken Säule: ${fmtNum(t1080)} min',
          LineChart(
            LineChartData(
              minX: 0,
              maxX: 100,
              minY: 0,
              gridData: grid,
              borderData: FlBorderData(show: false),
              titlesData: titles('Ladestand %', 'kW', 10),
              lineBarsData: [bar(curve, c.series1)],
            ),
          ),
        ),
        card(
          'Verbrauch bei konstanter Geschwindigkeit',
          'Ebene, ${fmtNum(widget.state.conditions.outsideTempC)} °C, '
              '${fmtNum(widget.state.conditions.payloadKg)} kg Zuladung · '
              '130 km/h: ${fmtNum(c130, 1)} kWh/100 km',
          LineChart(
            LineChartData(
              minX: 30,
              maxX: 200,
              minY: 0,
              gridData: grid,
              borderData: FlBorderData(show: false),
              titlesData: titles('km/h', 'kWh/100 km', 20),
              lineBarsData: [bar(cons, c.series1)],
            ),
          ),
        ),
        card(
          'Reichweite 100 → 0 %',
          'Theoretisch, bei konstanter Geschwindigkeit in der Ebene',
          LineChart(
            LineChartData(
              minX: 30,
              maxX: 200,
              minY: 0,
              gridData: grid,
              borderData: FlBorderData(show: false),
              titlesData: titles('km/h', 'km', 20),
              lineBarsData: [bar(range, c.series2)],
            ),
          ),
        ),
      ],
    );
  }
}

/// fl_chart labels the axis maximum even if it is not on the grid, which
/// makes it collide with the last regular label.
bool _offGrid(double v, TitleMeta meta) =>
    (v == meta.max || v == meta.min) &&
    (v / meta.appliedInterval - (v / meta.appliedInterval).round()).abs() >
        1e-6;
