import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

void main() {
  test('decodes the reference polyline from the Google docs', () {
    final p = decodePolyline(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(p.length, 3);
    expect(p[0].lat, closeTo(38.5, 1e-6));
    expect(p[0].lng, closeTo(-120.2, 1e-6));
    expect(p[2].lat, closeTo(43.252, 1e-6));
    expect(p[2].lng, closeTo(-126.453, 1e-6));
  });
  test('route labels are Arabic and rounded', () {
    final r = RouteInfo.fromJson({
      'polyline': '_p~iF~ps|U',
      'distanceMeters': 2400,
      'durationSeconds': 754,
    });
    expect(r.etaLabel, '13 دقيقة');
    expect(r.distanceLabel, '2.4 كم');
    expect(const RouteInfo([], 800, 20).distanceLabel, '800 م');
  });
}
