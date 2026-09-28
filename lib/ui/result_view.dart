import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../model/trip.dart';
import '../planner/optimizer.dart';
import 'format.dart';

class ResultView extends StatelessWidget {
  final TripRoute route;
  final OptimizationResult result;
  final TripConditions conditions;

  const ResultView({
    super.key,
    required this.route,
    required this.result,
    required this.conditions,
  });

  @override
  Widget build(BuildContext context) {
    final best = result.best;
    if (best == null) {
      return const Center(child: Text('Keine machbare Planung gefunden.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${route.startName} → ${route.destinationName}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          '${fmtNum(route.lengthM / 1000)} km · '
          '${route.chargers.length} Lader entlang der Strecke',
        ),
        for (final w in route.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(w)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _Summary(plan: best),
        const SizedBox(height: 16),
        _Recommendation(result: result),
        if (route.geometry.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'Karte',
            child: SizedBox(
              height: 380,
              child: _RouteMap(route: route, plan: best),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _Section(
          title: 'Ladestand entlang der Strecke',
          child: _SocChart(plan: best, conditions: conditions),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Reisezeit bei konstanter Reisegeschwindigkeit',
          subtitle:
              'Jeweils mit optimal gewählten Ladestopps. Die gestrichelte '
              'Linie ist das Optimum mit variabler Geschwindigkeit je Etappe.',
          child: _TradeoffChart(result: result),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Fahrplan',
          child: _Timeline(plan: best),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: t.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final TripPlan plan;
  const _Summary({required this.plan});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Gesamtzeit', fmtDuration(plan.totalHours), Icons.timer_outlined),
      ('Fahrzeit', fmtDuration(plan.driveHours), Icons.directions_car_outlined),
      (
        'Laden + Stopps',
        fmtDuration(plan.chargeHours + plan.overheadHours),
        Icons.ev_station_outlined,
      ),
      ('Ladestopps', '${plan.stops.length}', Icons.place_outlined),
      (
        'Energie',
        '${fmtNum(plan.energyKwh, 1)} kWh',
        Icons.battery_charging_full,
      ),
      (
        'Ø Verbrauch',
        '${fmtNum(plan.energyKwh / plan.distanceKm * 100, 1)} kWh/100 km',
        Icons.speed,
      ),
      ('Ankunft mit', '${fmtNum(plan.arrivalSoc)} %', Icons.flag_outlined),
    ];
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (label, value, icon) in tiles)
          SizedBox(
            width: 170,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 16),
                        const SizedBox(width: 6),
                        Flexible(child: Text(label, style: t.bodySmall)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(value, style: t.titleMedium),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Recommendation extends StatelessWidget {
  final OptimizationResult result;
  const _Recommendation({required this.result});

  @override
  Widget build(BuildContext context) {
    final best = result.best!;
    final speeds = best.legs.map((l) => l.cruiseKmh).toSet().toList()..sort();
    final speedText = speeds.length == 1
        ? '${fmtNum(speeds.first)} km/h'
        : '${fmtNum(speeds.first)}–${fmtNum(speeds.last)} km/h';

    final feasible = [
      for (final c in result.constantSpeed)
        if (c.plan != null) c,
    ];
    final lines = <String>[
      'Schnellste Strategie: auf Autobahn/Schnellstraße $speedText fahren '
          '(je Etappe unten im Fahrplan), ${best.stops.length} Ladestopp(s).',
    ];
    if (feasible.isNotEmpty) {
      final bestConst = feasible.reduce(
        (a, b) => a.plan!.totalHours <= b.plan!.totalHours ? a : b,
      );
      lines.add(
        'Beste konstante Geschwindigkeit: ${fmtNum(bestConst.kmh)} km/h '
        '→ ${fmtDuration(bestConst.plan!.totalHours)}.',
      );
      final relaxed = feasible.firstWhere(
        (c) => c.plan!.totalHours - best.totalHours <= 10 / 60,
        orElse: () => bestConst,
      );
      if (relaxed.kmh < bestConst.kmh) {
        lines.add(
          'Entspannter: konstant ${fmtNum(relaxed.kmh)} km/h kostet nur '
          '${fmtNum((relaxed.plan!.totalHours - best.totalHours) * 60)} min mehr '
          '(${relaxed.plan!.stops.length} Stopp(s)).',
        );
      }
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        l,
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteMap extends StatelessWidget {
  final TripRoute route;
  final TripPlan plan;
  const _RouteMap({required this.route, required this.plan});

  @override
  Widget build(BuildContext context) {
    final pts = [for (final c in route.geometry) LatLng(c[0], c[1])];
    final used = plan.stops.map((s) => s.charger).toSet();
    final colors = ChartColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return FlutterMap(
      key: ValueKey(route),
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(32),
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'de.chrbayer.trip_planner',
        ),
        PolylineLayer(
          polylines: [
            Polyline(points: pts, strokeWidth: 4, color: colors.series1),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final c in route.chargers)
              if (!used.contains(c))
                Marker(
                  point: LatLng(c.lat, c.lon),
                  width: 14,
                  height: 14,
                  child: Tooltip(
                    message: '${c.name} (${fmtNum(c.maxKw)} kW)',
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outline, width: 2),
                      ),
                    ),
                  ),
                ),
            for (final (i, s) in plan.stops.indexed)
              Marker(
                point: LatLng(s.charger.lat, s.charger.lon),
                width: 30,
                height: 30,
                child: Tooltip(
                  message:
                      '${s.charger.name}\n'
                      '${fmtNum(s.arrivalSoc)} % → ${fmtNum(s.departureSoc)} %, '
                      '${fmtDuration(s.chargeHours)}',
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.series2,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            Marker(
              point: pts.first,
              child: Icon(Icons.trip_origin, color: scheme.primary),
            ),
            Marker(
              point: pts.last,
              child: Icon(Icons.flag, color: scheme.error),
            ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap-Mitwirkende'),
        ),
      ],
    );
  }
}

FlTitlesData _titles(
  BuildContext context, {
  required String xUnit,
  required String yUnit,
  double? xInterval,
  double? yInterval,
}) {
  final style = Theme.of(context).textTheme.bodySmall;
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    bottomTitles: AxisTitles(
      axisNameWidget: Text(xUnit, style: style),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 24,
        interval: xInterval,
        getTitlesWidget: (v, meta) => _offGrid(v, meta)
            ? const SizedBox.shrink()
            : SideTitleWidget(
                meta: meta,
                child: Text(fmtNum(v), style: style),
              ),
      ),
    ),
    leftTitles: AxisTitles(
      axisNameWidget: Text(yUnit, style: style),
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 40,
        interval: yInterval,
        getTitlesWidget: (v, meta) => _offGrid(v, meta)
            ? const SizedBox.shrink()
            : SideTitleWidget(
                meta: meta,
                child: Text(fmtNum(v), style: style),
              ),
      ),
    ),
  );
}

FlGridData _grid(ChartColors c) => FlGridData(
  getDrawingHorizontalLine: (_) =>
      FlLine(color: c.grid.withValues(alpha: 0.5), strokeWidth: 1),
  getDrawingVerticalLine: (_) =>
      FlLine(color: c.grid.withValues(alpha: 0.5), strokeWidth: 1),
);

class _SocChart extends StatelessWidget {
  final TripPlan plan;
  final TripConditions conditions;
  const _SocChart({required this.plan, required this.conditions});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    final spots = [for (final p in plan.socTrace) FlSpot(p.km, p.soc)];
    final km = plan.distanceKm;
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: km,
          minY: 0,
          maxY: 100,
          gridData: _grid(c),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            context,
            xUnit: 'km',
            yUnit: 'Ladestand %',
            xInterval: _niceStep(km / 6),
            yInterval: 20,
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: conditions.minArrivalSocCharger,
                color: c.axisText,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    'km ${fmtNum(s.x)}: ${fmtNum(s.y)} %',
                    const TextStyle(color: Colors.white),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: c.series1,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: c.series1.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TradeoffChart extends StatelessWidget {
  final OptimizationResult result;
  const _TradeoffChart({required this.result});

  @override
  Widget build(BuildContext context) {
    final c = ChartColors.of(context);
    final pts = [
      for (final p in result.constantSpeed)
        if (p.plan != null) (kmh: p.kmh, plan: p.plan!),
    ];
    if (pts.isEmpty) return const Text('Keine Daten.');
    LineChartBarData bar(List<FlSpot> s, Color color) => LineChartBarData(
      spots: s,
      color: color,
      barWidth: 2,
      dotData: FlDotData(
        getDotPainter: (_, _, _, _) =>
            FlDotCirclePainter(radius: 3, color: color, strokeWidth: 0),
      ),
    );
    final total = [for (final p in pts) FlSpot(p.kmh, p.plan.totalHours * 60)];
    final drive = [for (final p in pts) FlSpot(p.kmh, p.plan.driveHours * 60)];
    final charge = [
      for (final p in pts)
        FlSpot(p.kmh, (p.plan.chargeHours + p.plan.overheadHours) * 60),
    ];
    final maxY = total.map((s) => s.y).reduce(math.max);
    final bestMin = result.best!.totalHours * 60;
    final names = ['Gesamt', 'Fahren', 'Laden + Stopps'];
    final colors = [c.series1, c.series2, c.series3];
    final t = Theme.of(context).textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          children: [
            for (var i = 0; i < 3; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 14, height: 3, color: colors[i]),
                  const SizedBox(width: 6),
                  Text(names[i], style: t),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: (maxY * 1.1 / 30).ceil() * 30,
              gridData: _grid(c),
              borderData: FlBorderData(show: false),
              titlesData: _titles(
                context,
                xUnit: 'Reisegeschwindigkeit km/h',
                yUnit: 'Minuten',
                xInterval: 10,
                yInterval: _niceStep(maxY / 5),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: bestMin,
                    color: c.axisText,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: t,
                      labelResolver: (_) =>
                          'Optimum ${fmtDuration(bestMin / 60)}',
                    ),
                  ),
                ],
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      LineTooltipItem(
                        '${names[s.barIndex]}: ${fmtDuration(s.y / 60)}'
                        '${s.barIndex == 0 ? ' @ ${fmtNum(s.x)} km/h, ${pts[s.spotIndex].plan.stops.length} Stopps' : ''}',
                        const TextStyle(color: Colors.white),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                bar(total, colors[0]),
                bar(drive, colors[1]),
                bar(charge, colors[2]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

double _niceStep(double raw) {
  if (raw <= 0) return 1;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 5, 10]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

class _Timeline extends StatelessWidget {
  final TripPlan plan;
  const _Timeline({required this.plan});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    var clock = 0.0;
    Widget row(
      IconData icon,
      Color color,
      String title,
      String detail,
      String time,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall),
                Text(detail, style: t.bodySmall),
              ],
            ),
          ),
          Text(time, style: t.bodySmall),
        ],
      ),
    );

    rows.add(
      row(
        Icons.trip_origin,
        scheme.primary,
        plan.legs.first.from,
        'Abfahrt mit ${fmtNum(plan.legs.first.departureSoc)} %',
        '+0:00',
      ),
    );
    for (var i = 0; i < plan.legs.length; i++) {
      final l = plan.legs[i];
      clock += l.hours;
      rows.add(
        row(
          Icons.arrow_downward,
          scheme.outline,
          'Reisegeschwindigkeit ${fmtNum(l.cruiseKmh)} km/h',
          '${fmtNum(l.distanceKm)} km in ${fmtDuration(l.hours)} '
              '(Ø ${fmtNum(l.avgKmh)} km/h) · ${fmtNum(l.kwh, 1)} kWh '
              '(${fmtNum(l.kwhPer100km, 1)} kWh/100 km) · '
              '${fmtNum(l.departureSoc)} % → ${fmtNum(l.arrivalSoc)} %',
          '',
        ),
      );
      if (i < plan.stops.length) {
        final s = plan.stops[i];
        rows.add(
          row(
            Icons.ev_station,
            ChartColors.of(context).series2,
            '${i + 1}. ${s.charger.name}',
            'km ${fmtNum(l.endKm)} · ${fmtNum(s.arrivalSoc)} % → '
                '${fmtNum(s.departureSoc)} % · ${fmtNum(s.kwhCharged, 1)} kWh '
                'in ${fmtDuration(s.chargeHours)} (Ø ${fmtNum(s.avgKw)} kW) · '
                '+${fmtDuration(s.overheadHours)} Umweg/Stopp · '
                'Säule ${fmtNum(s.charger.maxKw)} kW'
                '${s.charger.stalls > 0 ? ', ${s.charger.stalls} Plätze' : ''}',
            '+${_clock(clock)}',
          ),
        );
        clock += s.chargeHours + s.overheadHours;
      }
    }
    rows.add(
      row(
        Icons.flag,
        scheme.error,
        plan.legs.last.to,
        'Ankunft mit ${fmtNum(plan.arrivalSoc)} %',
        '+${_clock(clock)}',
      ),
    );
    return Column(children: rows);
  }

  static String _clock(double hours) {
    final m = (hours * 60).round();
    return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  }
}

/// fl_chart labels the axis maximum even if it is not on the grid, which
/// makes it collide with the last regular label.
bool _offGrid(double v, TitleMeta meta) =>
    (v == meta.max || v == meta.min) &&
    (v / meta.appliedInterval - (v / meta.appliedInterval).round()).abs() >
        1e-6;
