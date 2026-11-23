import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_nurse_app/alarm.dart';

void main() {
  final now = DateTime.utc(2026, 11, 21, 12, 0, 0);

  test('a new-request push becomes an alarm that lasts exactly as long as the offer', () {
    final a = AlarmData.from({'alarm': '1', 'offerId': 'o1', 'title': 'طلب', 'body': 'افتح', 'expiresAt': now.add(const Duration(seconds: 17)).toIso8601String(), 'ttl': '30'}, now: now)!;
    expect(a.ttlSeconds, 17);
    expect(a.notificationId, 10217);
  });

  test('stale offers and normal notifications never ring', () {
    expect(AlarmData.from({'alarm': '1', 'expiresAt': now.subtract(const Duration(seconds: 5)).toIso8601String()}, now: now), isNull);
    expect(AlarmData.from({'type': 'visit.arrive'}, now: now), isNull);
  });

  test('falls back to the TTL and is capped at one minute', () {
    expect(AlarmData.from({'alarm': '1', 'ttl': '20'}, now: now)!.ttlSeconds, 20);
    expect(AlarmData.from({'alarm': '1', 'ttl': '999'}, now: now)!.ttlSeconds, 60);
  });
}
