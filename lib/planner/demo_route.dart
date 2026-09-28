import '../model/trip.dart';

/// Synthetic motorway route without network access: flat, [lengthKm] long,
/// with a charger every [chargerSpacingKm].
TripRoute demoRoute({
  double lengthKm = 600,
  double chargerSpacingKm = 50,
  double chargerKw = 250,
  double detourKm = 1,
}) {
  final n = lengthKm.round();
  final segments = [
    for (var i = 0; i < n; i++)
      RouteSegment(
        lengthM: lengthKm * 1000 / n,
        climbM: 0,
        roadSpeedKmh: 120,
        lat: 0,
        lon: i / n,
      ),
  ];
  final chargers = [
    for (var km = chargerSpacingKm; km < lengthKm - 1; km += chargerSpacingKm)
      ChargerSite(
        name: 'Lader km ${km.round()}',
        lat: 0,
        lon: km / lengthKm,
        maxKw: chargerKw,
        stalls: 8,
        routePosM: km * 1000,
        detourM: detourKm * 1000,
      ),
  ];
  return TripRoute(
    startName: 'Start',
    destinationName: 'Ziel',
    segments: segments,
    chargers: chargers,
    geometry: const [],
  );
}
