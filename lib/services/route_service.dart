import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../model/trip.dart';
import 'geo.dart';
import 'http_client.dart';
import 'superchargers.dart';

class Place {
  final String name;
  final double lat;
  final double lon;
  const Place(this.name, this.lat, this.lon);
}

class RouteException implements Exception {
  final String message;
  RouteException(this.message);
  @override
  String toString() => message;
}

/// Builds a [TripRoute] from free-text start/destination using OSM services:
/// Nominatim (geocoding), OSRM (routing), Open-Meteo (elevation) and
/// supercharge.info (chargers).
class RouteService {
  final SuperchargerRepository superchargers;
  final void Function(String status)? onStatus;

  RouteService(this.superchargers, {this.onStatus});

  static const _segmentLengthM = 1000.0;

  Future<TripRoute> build(
    String from,
    String to, {
    double maxChargerOffsetKm = 5,
  }) async {
    onStatus?.call('Suche Orte …');
    final a = await geocode(from);
    final b = await geocode(to);

    onStatus?.call('Berechne Route …');
    final osrm = await _osrm(a, b);

    final segs = _resample(osrm);
    onStatus?.call('Lade Höhenprofil (${segs.length} km) …');
    final warnings = <String>[];
    List<double> elev;
    try {
      elev = await _boundaryElevations(segs, osrm.coords.last);
    } catch (e) {
      elev = List.filled(segs.length + 1, 0);
      warnings.add(
        'Höhenprofil nicht verfügbar ($e) – Strecke als eben '
        'gerechnet.',
      );
    }
    final segments = [
      for (var i = 0; i < segs.length; i++)
        RouteSegment(
          lengthM: segs[i].lengthM,
          climbM: elev[i + 1] - elev[i],
          roadSpeedKmh: segs[i].speedKmh,
          lat: segs[i].lat,
          lon: segs[i].lon,
        ),
    ];

    onStatus?.call('Suche Supercharger entlang der Route …');
    final sites = await superchargers.load();
    final chargers = _chargersAlong(osrm, sites, maxChargerOffsetKm * 1000);

    return TripRoute(
      startName: a.name,
      destinationName: b.name,
      segments: segments,
      chargers: chargers,
      geometry: osrm.coords,
      warnings: warnings,
    );
  }

  static final _latLon = RegExp(
    r'^\s*(-?\d+(?:\.\d+)?)\s*[,; ]\s*(-?\d+(?:\.\d+)?)\s*$',
  );

  Future<Place> geocode(String query) async {
    final m = _latLon.firstMatch(query);
    if (m != null) {
      return Place(query.trim(), double.parse(m[1]!), double.parse(m[2]!));
    }
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '1',
      'accept-language': 'de',
    });
    final resp = await http.get(uri, headers: userAgentHeaders);
    if (resp.statusCode != 200) {
      throw RouteException(
        'Ortssuche fehlgeschlagen (HTTP ${resp.statusCode})',
      );
    }
    final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
    if (list.isEmpty) throw RouteException('Ort nicht gefunden: "$query"');
    final r = list.first as Map<String, dynamic>;
    final display = r['display_name'] as String;
    return Place(
      display.split(',').take(2).join(',').trim(),
      double.parse(r['lat'] as String),
      double.parse(r['lon'] as String),
    );
  }

  Future<_OsrmRoute> _osrm(Place a, Place b) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${a.lon},${a.lat};${b.lon},${b.lat}'
      '?overview=full&geometries=geojson&annotations=distance,duration',
    );
    final resp = await http
        .get(uri, headers: userAgentHeaders)
        .timeout(const Duration(seconds: 60));
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    if (j['code'] != 'Ok') {
      throw RouteException(
        'Routing fehlgeschlagen: ${j['message'] ?? j['code']}',
      );
    }
    final route = (j['routes'] as List).first as Map<String, dynamic>;
    final coords = [
      for (final c in (route['geometry']['coordinates'] as List))
        [(c[1] as num).toDouble(), (c[0] as num).toDouble()],
    ];
    final dist = <double>[];
    final dur = <double>[];
    for (final leg in route['legs'] as List) {
      final ann = leg['annotation'] as Map<String, dynamic>;
      dist.addAll((ann['distance'] as List).map((e) => (e as num).toDouble()));
      dur.addAll((ann['duration'] as List).map((e) => (e as num).toDouble()));
    }
    return _OsrmRoute(coords, dist, dur);
  }

  /// Merges the fine OSRM geometry into ~1 km segments.
  List<_RawSeg> _resample(_OsrmRoute r) {
    final out = <_RawSeg>[];
    var len = 0.0, dur = 0.0;
    var startIdx = 0;
    for (var i = 0; i < r.dist.length; i++) {
      len += r.dist[i];
      dur += r.dur[i];
      final last = i == r.dist.length - 1;
      if (len >= _segmentLengthM || (last && len > 0)) {
        final speed = dur > 0 ? len / dur * 3.6 : 50.0;
        out.add(
          _RawSeg(
            r.coords[startIdx][0],
            r.coords[startIdx][1],
            len,
            speed.clamp(5.0, 140.0),
          ),
        );
        len = 0;
        dur = 0;
        startIdx = i + 1;
      }
    }
    return out;
  }

  /// Open-Meteo counts every coordinate against a limit of 600 per minute,
  /// so elevation is sampled at most [_maxElevationPoints] times and
  /// interpolated linearly to the segment boundaries in between.
  static const _maxElevationPoints = 400;

  Future<List<double>> _boundaryElevations(
    List<_RawSeg> segs,
    List<double> end,
  ) async {
    final pts = [
      for (final s in segs) [s.lat, s.lon],
      end,
    ];
    final cum = List<double>.filled(pts.length, 0);
    for (var i = 0; i < segs.length; i++) {
      cum[i + 1] = cum[i] + segs[i].lengthM;
    }
    final step = math.max(1, (pts.length / _maxElevationPoints).ceil());
    final idx = [
      for (var i = 0; i < pts.length - 1; i += step) i,
      pts.length - 1,
    ];
    final sampled = await _elevations([for (final i in idx) pts[i]]);
    final out = List<double>.filled(pts.length, 0);
    for (var k = 0; k + 1 < idx.length; k++) {
      final a = idx[k], b = idx[k + 1];
      for (var i = a; i <= b; i++) {
        final t = cum[b] > cum[a] ? (cum[i] - cum[a]) / (cum[b] - cum[a]) : 0;
        out[i] = sampled[k] + t * (sampled[k + 1] - sampled[k]);
      }
    }
    return out;
  }

  /// Elevations from Open-Meteo (Copernicus DEM, 90 m), 100 points per
  /// request. Requests run one after another because the free API
  /// rate-limits bursts.
  Future<List<double>> _elevations(List<List<double>> pts) async {
    const chunk = 100;
    final out = <double>[];
    for (var i = 0; i < pts.length; i += chunk) {
      onStatus?.call('Lade Höhenprofil ${(i / pts.length * 100).round()} % …');
      out.addAll(
        await _elevationChunk(pts.sublist(i, math.min(i + chunk, pts.length))),
      );
    }
    return out;
  }

  Future<List<double>> _elevationChunk(List<List<double>> pts) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
      'latitude': pts.map((p) => p[0].toStringAsFixed(5)).join(','),
      'longitude': pts.map((p) => p[1].toStringAsFixed(5)).join(','),
    });
    const backoff = [3, 20, 61];
    for (var attempt = 0; ; attempt++) {
      String problem;
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200) {
          final j = jsonDecode(resp.body) as Map<String, dynamic>;
          return [
            for (final e in j['elevation'] as List)
              (e as num?)?.toDouble() ?? 0,
          ];
        }
        problem = 'HTTP ${resp.statusCode}';
      } catch (e) {
        problem = e.toString();
      }
      if (attempt >= backoff.length) throw RouteException(problem);
      onStatus?.call(
        'Höhendaten: $problem – neuer Versuch in '
        '${backoff[attempt]} s …',
      );
      await Future.delayed(Duration(seconds: backoff[attempt]));
    }
  }

  List<ChargerSite> _chargersAlong(
    _OsrmRoute r,
    List<Supercharger> sites,
    double maxOffsetM,
  ) {
    // Cumulative distance per geometry point.
    final cum = List<double>.filled(r.coords.length, 0);
    for (var i = 0; i < r.dist.length && i + 1 < cum.length; i++) {
      cum[i + 1] = cum[i] + r.dist[i];
    }
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final c in r.coords) {
      minLat = math.min(minLat, c[0]);
      maxLat = math.max(maxLat, c[0]);
      minLon = math.min(minLon, c[1]);
      maxLon = math.max(maxLon, c[1]);
    }
    const pad = 0.1;
    final out = <ChargerSite>[];
    for (final s in sites) {
      if (s.lat < minLat - pad ||
          s.lat > maxLat + pad ||
          s.lon < minLon - pad ||
          s.lon > maxLon + pad) {
        continue;
      }
      var best = double.infinity;
      var bestIdx = 0;
      for (var i = 0; i < r.coords.length; i++) {
        final d = approxDistM(s.lat, s.lon, r.coords[i][0], r.coords[i][1]);
        if (d < best) {
          best = d;
          bestIdx = i;
        }
      }
      if (best > maxOffsetM) continue;
      // Road detour there and back; at least a few hundred metres for the
      // exit and car park.
      final detour = math.max(400.0, best * 2 * 1.4);
      out.add(
        ChargerSite(
          name: s.name,
          lat: s.lat,
          lon: s.lon,
          maxKw: s.kw,
          stalls: s.stalls,
          routePosM: cum[bestIdx],
          detourM: detour,
        ),
      );
    }
    out.sort((a, b) => a.routePosM.compareTo(b.routePosM));
    return out;
  }
}

class _OsrmRoute {
  final List<List<double>> coords;
  final List<double> dist;
  final List<double> dur;
  _OsrmRoute(this.coords, this.dist, this.dur);
}

class _RawSeg {
  final double lat, lon, lengthM, speedKmh;
  _RawSeg(this.lat, this.lon, this.lengthM, this.speedKmh);
}
