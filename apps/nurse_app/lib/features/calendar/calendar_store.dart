import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class CalendarStore extends ChangeNotifier {
  final TamreedyApi api;

  CalendarStore({required this.api});

  bool loading = false;
  String? error;
  List<Map<String, dynamic>> items = const [];
  int _sessionGen = 0;
  int _loadGeneration = 0;

  void resetForSessionChange() {
    _sessionGen++;
    items = const [];
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<void> load() async {
    if (kDemoMode) {
      items = const [];
      notifyListeners();
      return;
    }
    final gen = _sessionGen;
    final load = ++_loadGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).toIso8601String();
      final to = DateTime(now.year, now.month, now.day + 7).toIso8601String();
      final res = await api.getMap('/v1/nurse-calendar?from=$from&to=$to');
      if (gen != _sessionGen || load != _loadGeneration) return;
      final combined = <Map<String, dynamic>>[];

      for (final raw in (res['visits'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final v = Map<String, dynamic>.from(raw);
        final startStr = (v['plannedStartAt'] ?? v['planned_start_at'] ?? v['appointment_at'])?.toString();
        final mins = num.tryParse('${v['expected_minutes'] ?? ''}')?.toInt();
        final startDt = startStr != null ? DateTime.tryParse(startStr) : null;
        final endStr = (v['plannedEndAt'] ?? v['planned_end_at'])?.toString() ??
            (startDt != null && mins != null ? startDt.add(Duration(minutes: mins)).toIso8601String() : null);
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
      if (gen != _sessionGen || load != _loadGeneration) return;
      error = explainError(e, fallback: 'تعذر تحميل التقويم من الخادم');
    } finally {
      if (gen == _sessionGen && load == _loadGeneration) {
        loading = false;
        notifyListeners();
      }
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
