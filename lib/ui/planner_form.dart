import 'package:flutter/material.dart';

import '../app_state.dart';
import '../model/trip.dart';
import 'format.dart';

class PlannerForm extends StatefulWidget {
  final AppState state;
  final VoidCallback onPlanned;
  const PlannerForm({super.key, required this.state, required this.onPlanned});

  @override
  State<PlannerForm> createState() => _PlannerFormState();
}

class _PlannerFormState extends State<PlannerForm> {
  late final _from = TextEditingController(text: widget.state.from);
  late final _to = TextEditingController(text: widget.state.to);

  AppState get s => widget.state;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    s.update(() {
      s.from = _from.text.trim();
      s.to = _to.text.trim();
    });
    await s.plan();
    if (s.result?.best != null) widget.onPlanned();
  }

  @override
  Widget build(BuildContext context) {
    final c = s.conditions;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SegmentedButton<RouteMode>(
          segments: const [
            ButtonSegment(
              value: RouteMode.real,
              icon: Icon(Icons.map_outlined),
              label: Text('Echte Route'),
            ),
            ButtonSegment(
              value: RouteMode.demo,
              icon: Icon(Icons.straighten),
              label: Text('Demo-Strecke'),
            ),
          ],
          selected: {s.mode},
          onSelectionChanged: (v) => s.update(() => s.mode = v.first),
        ),
        const SizedBox(height: 16),
        if (s.mode == RouteMode.real) ...[
          TextField(
            controller: _from,
            decoration: const InputDecoration(
              labelText: 'Start',
              prefixIcon: Icon(Icons.trip_origin),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.next,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Start und Ziel tauschen',
              icon: const Icon(Icons.swap_vert),
              onPressed: () {
                final t = _from.text;
                _from.text = _to.text;
                _to.text = t;
              },
            ),
          ),
          TextField(
            controller: _to,
            decoration: const InputDecoration(
              labelText: 'Ziel',
              prefixIcon: Icon(Icons.flag_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _plan(),
          ),
          const SizedBox(height: 8),
          _slider(
            'Max. Umweg zum Supercharger (Luftlinie)',
            s.maxChargerOffsetKm,
            1,
            20,
            19,
            (v) => s.update(() => s.maxChargerOffsetKm = v),
            unit: 'km',
          ),
        ] else ...[
          _slider(
            'Streckenlänge',
            s.demo.lengthKm,
            100,
            1500,
            28,
            (v) => s.update(
              () => s.demo = DemoParams(
                lengthKm: v,
                spacingKm: s.demo.spacingKm,
                chargerKw: s.demo.chargerKw,
              ),
            ),
            unit: 'km',
          ),
          _slider(
            'Abstand der Lader',
            s.demo.spacingKm,
            20,
            200,
            18,
            (v) => s.update(
              () => s.demo = DemoParams(
                lengthKm: s.demo.lengthKm,
                spacingKm: v,
                chargerKw: s.demo.chargerKw,
              ),
            ),
            unit: 'km',
          ),
          _slider(
            'Ladeleistung der Säulen',
            s.demo.chargerKw,
            50,
            350,
            12,
            (v) => s.update(
              () => s.demo = DemoParams(
                lengthKm: s.demo.lengthKm,
                spacingKm: s.demo.spacingKm,
                chargerKw: v,
              ),
            ),
            unit: 'kW',
          ),
        ],
        const Divider(height: 32),
        Text('Akku', style: theme.textTheme.titleSmall),
        _slider(
          'Ladestand bei Abfahrt',
          c.startSoc,
          10,
          100,
          90,
          (v) => _cond(c.copyWith(startSoc: v)),
          unit: '%',
        ),
        _slider(
          'Mindestens bei Ankunft am Lader',
          c.minArrivalSocCharger,
          2,
          30,
          28,
          (v) => _cond(c.copyWith(minArrivalSocCharger: v)),
          unit: '%',
        ),
        _slider(
          'Mindestens bei Ankunft am Ziel',
          c.minArrivalSocDestination,
          2,
          80,
          78,
          (v) => _cond(c.copyWith(minArrivalSocDestination: v)),
          unit: '%',
        ),
        _slider(
          'Höchstens laden bis',
          c.maxChargeSoc,
          50,
          100,
          50,
          (v) => _cond(c.copyWith(maxChargeSoc: v)),
          unit: '%',
        ),
        const Divider(height: 32),
        Text('Bedingungen', style: theme.textTheme.titleSmall),
        _slider(
          'Außentemperatur',
          c.outsideTempC,
          -20,
          40,
          60,
          (v) => _cond(c.copyWith(outsideTempC: v)),
          unit: '°C',
        ),
        _slider(
          'Gegenwind (negativ = Rückenwind)',
          c.headwindKmh,
          -30,
          50,
          16,
          (v) => _cond(c.copyWith(headwindKmh: v)),
          unit: 'km/h',
        ),
        _slider(
          'Zuladung',
          c.payloadKg,
          0,
          600,
          24,
          (v) => _cond(c.copyWith(payloadKg: v)),
          unit: 'kg',
        ),
        const Divider(height: 32),
        Text('Fahrweise', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DropdownButtonFormField<double?>(
          initialValue: c.speedLimitKmh,
          decoration: const InputDecoration(
            labelText: 'Tempolimit auf Autobahn/Schnellstraße',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: null, child: Text('keins')),
            DropdownMenuItem(value: 100.0, child: Text('100 km/h')),
            DropdownMenuItem(value: 110.0, child: Text('110 km/h')),
            DropdownMenuItem(value: 120.0, child: Text('120 km/h')),
            DropdownMenuItem(value: 130.0, child: Text('130 km/h')),
            DropdownMenuItem(value: 150.0, child: Text('150 km/h')),
          ],
          onChanged: (v) => _cond(c.copyWith(speedLimitKmh: () => v)),
        ),
        const SizedBox(height: 8),
        _slider(
          'Höchste Reisegeschwindigkeit',
          c.maxCruiseKmh,
          100,
          200,
          20,
          (v) => _cond(c.copyWith(maxCruiseKmh: v)),
          unit: 'km/h',
        ),
        _slider(
          'Zeitverlust pro Ladestopp (ohne Laden)',
          c.stopOverheadMin,
          0,
          20,
          20,
          (v) => _cond(c.copyWith(stopOverheadMin: v)),
          unit: 'min',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: s.busy ? null : _plan,
          icon: s.busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.bolt),
          label: Text(s.busy ? (s.status ?? 'Rechne …') : 'Route planen'),
        ),
        if (s.error != null) ...[
          const SizedBox(height: 12),
          Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  void _cond(TripConditions next) => s.update(() => s.conditions = next);

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged, {
    required String unit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                '${fmtNum(value)} $unit',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
