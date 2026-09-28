import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'http_client.dart';

class Supercharger {
  final String name;
  final double lat;
  final double lon;
  final double kw;
  final int stalls;
  const Supercharger(this.name, this.lat, this.lon, this.kw, this.stalls);
}

/// Loads all open Tesla Superchargers from supercharge.info and caches them
/// on disk for [maxAge].
class SuperchargerRepository {
  static const _url = 'https://supercharge.info/service/supercharge/allSites';
  static const maxAge = Duration(days: 14);

  /// Cache directory; defaults to the app support directory.
  final Directory? cacheDir;

  SuperchargerRepository({this.cacheDir});

  List<Supercharger>? _sites;

  Future<List<Supercharger>> load() async {
    if (_sites != null) return _sites!;
    final dir = cacheDir ?? await getApplicationSupportDirectory();
    final file = File('${dir.path}/superchargers.json');
    String? raw;
    if (await file.exists() &&
        DateTime.now().difference(await file.lastModified()) < maxAge) {
      raw = await file.readAsString();
    } else {
      try {
        final resp = await http
            .get(Uri.parse(_url), headers: userAgentHeaders)
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode != 200) {
          throw HttpException('supercharge.info: HTTP ${resp.statusCode}');
        }
        raw = utf8.decode(resp.bodyBytes);
        await dir.create(recursive: true);
        await file.writeAsString(raw);
      } catch (_) {
        // Fall back to a stale cache if there is one.
        if (await file.exists()) {
          raw = await file.readAsString();
        } else {
          rethrow;
        }
      }
    }
    _sites = await _parseInBackground(raw);
    return _sites!;
  }
}

List<Supercharger> parseSites(String raw) {
  final list = jsonDecode(raw) as List;
  final out = <Supercharger>[];
  for (final e in list) {
    final m = e as Map<String, dynamic>;
    if (m['status'] != 'OPEN') continue;
    final gps = m['gps'] as Map<String, dynamic>?;
    if (gps == null) continue;
    out.add(
      Supercharger(
        'Supercharger ${m['name']}',
        (gps['latitude'] as num).toDouble(),
        (gps['longitude'] as num).toDouble(),
        (m['powerKilowatt'] as num?)?.toDouble() ?? 150,
        (m['stallCount'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return out;
}

Future<List<Supercharger>> _parseInBackground(String raw) =>
    Isolate.run(() => parseSites(raw));
