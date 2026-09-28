/// Environment and driver preferences for one trip.
class TripConditions {
  /// State of charge at departure (0..100 %).
  final double startSoc;

  /// Minimum state of charge when arriving at a charger (0..100 %).
  final double minArrivalSocCharger;

  /// Minimum state of charge when arriving at the destination (0..100 %).
  final double minArrivalSocDestination;

  /// Maximum state of charge to charge to at a charger (0..100 %).
  final double maxChargeSoc;

  final double outsideTempC;

  /// Headwind component in km/h (negative = tailwind).
  final double headwindKmh;

  /// Passengers and luggage in kg on top of the vehicle mass.
  final double payloadKg;

  /// General speed limit on fast roads (null = none, e.g. German Autobahn).
  final double? speedLimitKmh;

  /// Fixed time lost per charging stop (pull in, plug in, pay) in minutes.
  final double stopOverheadMin;

  /// Lowest and highest cruise speed the optimizer may choose, in km/h.
  final double minCruiseKmh;
  final double maxCruiseKmh;

  const TripConditions({
    this.startSoc = 90,
    this.minArrivalSocCharger = 8,
    this.minArrivalSocDestination = 15,
    this.maxChargeSoc = 100,
    this.outsideTempC = 15,
    this.headwindKmh = 0,
    this.payloadKg = 100,
    this.speedLimitKmh,
    this.stopOverheadMin = 5,
    this.minCruiseKmh = 80,
    this.maxCruiseKmh = 150,
  });

  TripConditions copyWith({
    double? startSoc,
    double? minArrivalSocCharger,
    double? minArrivalSocDestination,
    double? maxChargeSoc,
    double? outsideTempC,
    double? headwindKmh,
    double? payloadKg,
    double? Function()? speedLimitKmh,
    double? stopOverheadMin,
    double? minCruiseKmh,
    double? maxCruiseKmh,
  }) => TripConditions(
    startSoc: startSoc ?? this.startSoc,
    minArrivalSocCharger: minArrivalSocCharger ?? this.minArrivalSocCharger,
    minArrivalSocDestination:
        minArrivalSocDestination ?? this.minArrivalSocDestination,
    maxChargeSoc: maxChargeSoc ?? this.maxChargeSoc,
    outsideTempC: outsideTempC ?? this.outsideTempC,
    headwindKmh: headwindKmh ?? this.headwindKmh,
    payloadKg: payloadKg ?? this.payloadKg,
    speedLimitKmh: speedLimitKmh != null ? speedLimitKmh() : this.speedLimitKmh,
    stopOverheadMin: stopOverheadMin ?? this.stopOverheadMin,
    minCruiseKmh: minCruiseKmh ?? this.minCruiseKmh,
    maxCruiseKmh: maxCruiseKmh ?? this.maxCruiseKmh,
  );

  Map<String, dynamic> toJson() => {
    'startSoc': startSoc,
    'minArrivalSocCharger': minArrivalSocCharger,
    'minArrivalSocDestination': minArrivalSocDestination,
    'maxChargeSoc': maxChargeSoc,
    'outsideTempC': outsideTempC,
    'headwindKmh': headwindKmh,
    'payloadKg': payloadKg,
    'speedLimitKmh': speedLimitKmh,
    'stopOverheadMin': stopOverheadMin,
    'minCruiseKmh': minCruiseKmh,
    'maxCruiseKmh': maxCruiseKmh,
  };

  factory TripConditions.fromJson(Map<String, dynamic> j) {
    const def = TripConditions();
    double d(String k, double fallback) =>
        (j[k] as num?)?.toDouble() ?? fallback;
    return TripConditions(
      startSoc: d('startSoc', def.startSoc),
      minArrivalSocCharger: d('minArrivalSocCharger', def.minArrivalSocCharger),
      minArrivalSocDestination: d(
        'minArrivalSocDestination',
        def.minArrivalSocDestination,
      ),
      maxChargeSoc: d('maxChargeSoc', def.maxChargeSoc),
      outsideTempC: d('outsideTempC', def.outsideTempC),
      headwindKmh: d('headwindKmh', def.headwindKmh),
      payloadKg: d('payloadKg', def.payloadKg),
      speedLimitKmh: (j['speedLimitKmh'] as num?)?.toDouble(),
      stopOverheadMin: d('stopOverheadMin', def.stopOverheadMin),
      minCruiseKmh: d('minCruiseKmh', def.minCruiseKmh),
      maxCruiseKmh: d('maxCruiseKmh', def.maxCruiseKmh),
    );
  }
}

/// One piece of the route, typically ~1 km long.
class RouteSegment {
  final double lengthM;

  /// Elevation change over the segment in m (positive = uphill).
  final double climbM;

  /// Typical speed on this road according to the router, in km/h.
  final double roadSpeedKmh;

  /// Start coordinate of the segment.
  final double lat;
  final double lon;

  const RouteSegment({
    required this.lengthM,
    required this.climbM,
    required this.roadSpeedKmh,
    required this.lat,
    required this.lon,
  });

  /// Motorway-like road where the driver's chosen cruise speed applies.
  bool get isFastRoad => roadSpeedKmh >= fastRoadThresholdKmh;

  static const fastRoadThresholdKmh = 88.0;
}

/// A charger next to the route.
class ChargerSite {
  final String name;
  final double lat;
  final double lon;

  /// Maximum power per stall in kW.
  final double maxKw;
  final int stalls;

  /// Distance along the route (m) where the car leaves the route.
  final double routePosM;

  /// Additional driving distance (there and back) in m.
  final double detourM;

  const ChargerSite({
    required this.name,
    required this.lat,
    required this.lon,
    required this.maxKw,
    required this.stalls,
    required this.routePosM,
    required this.detourM,
  });
}

/// A route with elevation and road speeds, plus the chargers along it.
class TripRoute {
  final String startName;
  final String destinationName;
  final List<RouteSegment> segments;
  final List<ChargerSite> chargers;

  /// Full geometry for map display as [lat, lon] pairs.
  final List<List<double>> geometry;

  /// Data quality notes to show to the user.
  final List<String> warnings;

  const TripRoute({
    required this.startName,
    required this.destinationName,
    required this.segments,
    required this.chargers,
    required this.geometry,
    this.warnings = const [],
  });

  double get lengthM => segments.fold(0.0, (s, e) => s + e.lengthM);
}
