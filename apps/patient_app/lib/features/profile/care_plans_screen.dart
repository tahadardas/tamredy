import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class CarePlansScreen extends StatefulWidget {
  final TamreedyApi api;

  const CarePlansScreen({super.key, required this.api});

  @override
  State<CarePlansScreen> createState() => _CarePlansScreenState();
}

class _CarePlansScreenState extends State<CarePlansScreen> {
  final List<Map<String, dynamic>> _plans = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (kDemoMode) {
      _loading = false;
      return;
    }
    try {
      final res = await widget.api.getMap('/v1/care-plans');
      final raw = res['plans'];
      if (raw is List) {
        _plans
          ..clear()
          ..addAll(raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
      }
    } catch (e) {
      _error = explainError(e, fallback: 'تعذر تحميل خطط الرعاية');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(String planId, String action) async {
    try {
      await widget.api.post('/v1/care-plans/$planId/$action', {});
      await _load();
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TamScaffold(
      title: 'خطط الرعاية المستمرة',
      subtitle: 'متابعة الزيارات التمريضية الدورية',
      showBack: true,
      onRefresh: _load,
      children: [
        if (_loading)
          const TamSkeleton.card(height: 120)
        else if (_error != null)
          TamErrorState(title: 'تعذر تحميل الخطط', message: _error!, onRetry: _load)
        else if (_plans.isEmpty)
          const TamEmptyState(
            icon: Icons.calendar_today_outlined,
            title: 'لا توجد خطط رعاية متكررة',
            message: 'ستظهر خطط الزيارات الدورية المجدولة هنا عند تفعيلها.',
          )
        else
          for (final p in _plans) ...[
            AeroCarePlanCard(
              title: '${p['title'] ?? 'خطة رعاية'}',
              frequency: '${p['frequency'] ?? 'أسبوعي'}',
              totalVisits: (num.tryParse('${p['total_occurrences'] ?? 0}') ?? 0).toInt(),
              completedVisits: (num.tryParse('${p['completed_occurrences'] ?? 0}') ?? 0).toInt(),
              status: '${p['status'] ?? 'ACTIVE'}',
              nextVisitAt: DateTime.tryParse('${p['next_occurrence_at'] ?? ''}'),
              onTap: () {
                final status = '${p['status'] ?? 'ACTIVE'}';
                final id = '${p['id'] ?? ''}';
                if (id.isEmpty) return;
                if (status == 'ACTIVE') {
                  _updateStatus(id, 'pause');
                } else if (status == 'PAUSED') {
                  _updateStatus(id, 'resume');
                }
              },
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}
