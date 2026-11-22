/// Decodes a Google encoded polyline (precision 1e5) into [lat, lng] pairs.
List<({double lat, double lng})> decodePolyline(String encoded) {
  final out = <({double lat, double lng})>[];
  var index = 0, lat = 0, lng = 0;
  int next() {
    var result = 0, shift = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += next();
    lng += next();
    out.add((lat: lat / 1e5, lng: lng / 1e5));
  }
  return out;
}

/// Server response of `/v1/requests/:id/route` and `/v1/nurse/assignments/:id/route`.
class RouteInfo {
  final List<({double lat, double lng})> points;
  final int distanceMeters;
  final int durationSeconds;
  const RouteInfo(this.points, this.distanceMeters, this.durationSeconds);

  factory RouteInfo.fromJson(Map<String, dynamic> j) => RouteInfo(
    decodePolyline(j['polyline'] as String),
    (j['distanceMeters'] as num).toInt(),
    (j['durationSeconds'] as num).toInt(),
  );

  String get etaLabel {
    final m = (durationSeconds / 60).ceil();
    return m < 1 ? 'أقل من دقيقة' : '$m دقيقة';
  }

  String get distanceLabel => distanceMeters < 1000
      ? '$distanceMeters م'
      : '${(distanceMeters / 1000).toStringAsFixed(1)} كم';
}
