import 'package:flutter/material.dart';

String fmtDuration(double hours) {
  final totalMin = (hours * 60).round();
  final h = totalMin ~/ 60, m = totalMin % 60;
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}

String fmtNum(double v, [int digits = 0]) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

/// Chart series colors (validated categorical palette), per brightness.
class ChartColors {
  final Color series1, series2, series3, grid, axisText;
  const ChartColors._(
    this.series1,
    this.series2,
    this.series3,
    this.grid,
    this.axisText,
  );

  factory ChartColors.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return dark
        ? ChartColors._(
            const Color(0xFF3987E5),
            const Color(0xFFD95926),
            const Color(0xFF199E70),
            scheme.outlineVariant,
            scheme.onSurfaceVariant,
          )
        : ChartColors._(
            const Color(0xFF2A78D6),
            const Color(0xFFEB6834),
            const Color(0xFF1BAF7A),
            scheme.outlineVariant,
            scheme.onSurfaceVariant,
          );
  }
}
