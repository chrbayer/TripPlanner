import 'package:flutter/material.dart';

import 'app_state.dart';
import 'ui/planner_form.dart';
import 'ui/result_view.dart';
import 'ui/vehicle_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState()..load();
  runApp(TripPlannerApp(state: state));
}

class TripPlannerApp extends StatelessWidget {
  final AppState state;
  const TripPlannerApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2A78D6),
        brightness: b,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'E-Trip Planer',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomePage(state: state),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppState state;
  const HomePage({super.key, required this.state});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 1000;
          final form = PlannerForm(
            state: s,
            onPlanned: () {
              if (!wide) _tabs.animateTo(1);
            },
          );
          final results = _results(context);
          return Scaffold(
            appBar: AppBar(
              title: const Text('E-Trip Planer'),
              actions: [
                if (wide)
                  TextButton.icon(
                    onPressed: () => _openVehicle(context),
                    icon: const Icon(Icons.electric_car),
                    label: Text(_shortName(s.vehicle.name)),
                  )
                else
                  IconButton(
                    tooltip: s.vehicle.name,
                    onPressed: () => _openVehicle(context),
                    icon: const Icon(Icons.electric_car),
                  ),
                const SizedBox(width: 8),
              ],
              bottom: wide
                  ? null
                  : TabBar(
                      controller: _tabs,
                      tabs: const [
                        Tab(text: 'Planung'),
                        Tab(text: 'Ergebnis'),
                      ],
                    ),
            ),
            body: wide
                ? Row(
                    children: [
                      SizedBox(width: 400, child: form),
                      const VerticalDivider(width: 1),
                      Expanded(child: results),
                    ],
                  )
                : TabBarView(controller: _tabs, children: [form, results]),
          );
        },
      ),
    );
  }

  void _openVehicle(BuildContext context) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => VehiclePage(state: widget.state)));

  static String _shortName(String name) {
    final i = name.indexOf('(');
    return i > 0 ? name.substring(0, i).trim() : name;
  }

  Widget _results(BuildContext context) {
    final s = widget.state;
    if (s.busy) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(s.status ?? ''),
          ],
        ),
      );
    }
    if (s.result == null || s.route == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Start und Ziel eingeben und „Route planen“ drücken.\n\n'
            'Die App wählt Reisegeschwindigkeit, Ladestopps und Lademengen so, '
            'dass die Gesamtreisezeit minimal wird.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ResultView(
      route: s.route!,
      result: s.result!,
      conditions: s.conditions,
    );
  }
}
