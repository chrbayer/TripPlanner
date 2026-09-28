# E-Trip Planer

Flutter-App (Linux, Android), die für ein E-Auto Reisegeschwindigkeit, Ladestopps
und Lademengen so wählt, dass die Gesamtreisezeit minimal wird.

## Modell

- **Verbrauch** (`lib/model/physics.dart`): Luftwiderstand (cW·A, Luftdichte
  aus Temperatur, Gegenwind), Rollwiderstand, Steigung/Gefälle mit begrenzter
  Rekuperation, Antriebswirkungsgrad, Nebenverbraucher und Heizung/Klima.
- **Laden**: SoC-abhängige Ladekurve, begrenzt durch die Säulenleistung,
  integriert in 0,25-%-Schritten.
- **Optimierung** (`lib/planner/optimizer.dart`): dynamische Programmierung über
  (Knoten, Ankunfts-SoC in 1-%-Schritten). Knoten sind Start, Lader und Ziel.
  Je Etappe wird eine Reisegeschwindigkeit (5-km/h-Raster) gewählt und am Lader
  auf einen beliebigen höheren SoC geladen. Zusätzlich wird für jede konstante
  Geschwindigkeit der beste Plan berechnet, um den Zielkonflikt sichtbar zu machen.

## Datenquellen (ohne API-Key)

| Zweck | Dienst |
|---|---|
| Ortssuche | Nominatim (OpenStreetMap) |
| Route, Straßentempo | OSRM Demo-Server |
| Höhenprofil | Open-Meteo Elevation (max. 600 Punkte/min, daher höchstens 400 Stützpunkte je Route) |
| Supercharger | supercharge.info (14 Tage lokal gecacht) |
| Karte | OpenStreetMap-Kacheln |

Die Geschwindigkeitswahl gilt nur auf schnellen Straßen (OSRM-Tempo ≥ 88 km/h).
Auf den übrigen Straßen wird das OSRM-Tempo gefahren.

## Fahrzeug: Tesla Model Y Standard RWD 2026 (CATL LFP)

60,5 kWh netto, 1981 kg inkl. Fahrer, cW 0,23, A 2,57 m², DC max. 175 kW.
Verbrauch kalibriert auf ~20 kWh/100 km bei 130 km/h. Ladekurve aus dem
[evkx.net-Ladekurvendiagramm](https://evkx.net/models/tesla/model_y/model_y_standard/chargingcurve/)
(1-%-Raster): 10→80 % ≈ 29 min.
Alle Werte sind in der App unter „Fahrzeug“ änderbar.

## Entwicklung

```sh
flutter test                                   # Physik- und Optimierer-Tests
flutter test test/route_online_test.dart --dart-define=ONLINE=true
flutter test test/screenshot_test.dart --dart-define=OUT=/tmp/shots [--dart-define=ONLINE=true]
```

## Bauen

```sh
./build_desktop.sh           # Linux → dist/trip_planner-<version>-linux-x64.tar.gz
./build_android.sh           # Android → dist/trip_planner-<version>.apk (universal)
./build_android.sh --github  # zusätzlich je eine APK pro ABI, alle ins GitHub-Release
```

Beide Skripte nehmen die Version aus `pubspec.yaml` und bauen mit `--debug`
eine Debug-Version.

Die Android-`versionCode` ist Build-Nummer × 10 plus eine Ziffer: 0 für die
universelle APK, 1 armeabi-v7a, 2 arm64-v8a, 3 x86_64. So lässt sich jede
neuere Version über jede Variante einer älteren installieren.

`--github` prüft vor dem Bauen: Keystore gesetzt, keine offenen Änderungen,
HEAD steht auf dem Tag `v<version>` und der Tag ist auf GitHub. Dann baut es,
prüft die Signaturen und lädt die APKs ins Release (legt es an, falls es noch
nicht existiert). Vorhandene Dateien werden nie überschrieben.

### Android-Release signieren

Der Release-Schlüssel liegt außerhalb des Repos. `build_android.sh` schreibt
`android/key.properties` nur für die Dauer des Builds und prüft danach mit
`apksigner`, welcher Schlüssel verwendet wurde. Im eigenen Terminal, nicht über
ein Werkzeug, das die Eingaben mitliest:

```sh
export TP_KEYSTORE_PASS="$(systemd-ask-password 'Kennwort:')"
export TP_KEYSTORE_PATH=~/keys/tripplanner-release.jks
./build_android.sh --github
```

Ohne `TP_KEYSTORE_PATH` wird mit dem Debug-Schlüssel signiert (mit Warnung).
Eine so installierte App lässt sich nicht durch eine richtig signierte
aktualisieren.

## Hinweis Linux: App startet nicht, 100 % CPU

Hängt die App vor dem ersten Fenster in `FcPatternGetString`, ist der
Fontconfig-Cache inkonsistent (z. B. `*.cache-9`-Symlinks auf `*.cache-12`
in `~/.cache/fontconfig`). Abhilfe:

```sh
find ~/.cache/fontconfig -type l -name '*.cache-9' -delete && fc-cache -f
```

## Lizenz

GNU General Public License v3.0, siehe [LICENSE](LICENSE).
