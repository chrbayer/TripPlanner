import 'dart:math' as math;

/// Great-circle distance in metres.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = p2 - p1, dl = (lon2 - lon1) * math.pi / 180;
  final a =
      math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// Fast approximate distance for nearby points (equirectangular), in metres.
double approxDistM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final x =
      (lon2 - lon1) *
      math.pi /
      180 *
      math.cos((lat1 + lat2) / 2 * math.pi / 180);
  final y = (lat2 - lat1) * math.pi / 180;
  return r * math.sqrt(x * x + y * y);
}
