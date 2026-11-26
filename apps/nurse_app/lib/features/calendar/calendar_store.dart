import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class CalendarStore extends ChangeNotifier {
  final TamreedyApi api;

  CalendarStore({required this.api});

  bool loading = false;
  String? error;
  List<Map<String, dynamic>> items = const [];

  Future<void> load() async {
    if (kDemoMode) {
      items = const [];
      notifyListeners();
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).toIso8601String();
      final to = DateTime(now.year, now.month, now.day + 7).toIso8601String();
      final res = await api.getMap('/v1/nurse-calendar?from=$from&to=$to');
      final combined = <Map<String, dynamic>>[];

      for (final raw in (res['visits'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final v = Map<String, dynamic>.from(raw);
        final startStr = (v['appointment_at'] ?? v['accepted_at'])?.toString();
        final mins = (num.tryParse('${v['expected_minutes'] ?? 45}') ?? 45).toInt();
        final startDt = startStr != null ? DateTime.tryParse(startStr) : null;
        final endStr = startDt?.add(Duration(minutes: mins)).toIso8601String();
        combined.add({
          'id': v['request_id'],
          'block_type': 'SCHEDULED_VISIT',
          'title': '${v['service_title'] ?? 'زيارة تمريضية'} — ${v['beneficiary_name'] ?? 'المريض'}',
          'start_time': startStr,
          'end_time': endStr,
        });
      }

      for (final raw in (res['blocks'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final b = Map<String, dynamic>.from(raw);
        combined.add({
          'id': b['id'],
          'block_type': 'BUSY_PERSONAL',
          'title': '${b['reason'] ?? ''}'.trim().isNotEmpty ? '${b['reason']}'.trim() : 'انشغال شخصي',
          'start_time': b['start_time'],
          'end_time': b['end_time'],
        });
      }

      combined.sort((a, b) => '${a['start_time'] ?? ''}'.compareTo('${b['start_time'] ?? ''}'));
      items = combined;
      error = null;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحميل التقويم من الخادم');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> addBusyBlock({
    required DateTime start,
    required DateTime end,
    String? reason,
  }) async {
    await api.post('/v1/nurse-calendar/blocks', {
      'startTime': start.toUtc().toIso8601String(),
      'endTime': end.toUtc().toIso8601String(),
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    await load();
  }

  Future<void> deleteBlock(String id) async {
    await api.delete('/v1/nurse-calendar/blocks/$id');
    await load();
  }
}
