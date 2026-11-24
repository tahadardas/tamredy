import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class CarePlansScreen extends StatefulWidget {
  final PatientController c;

  const CarePlansScreen({super.key, required this.c});

  @override
  State<CarePlansScreen> createState() => _CarePlansScreenState();
}

class _CarePlansScreenState extends State<CarePlansScreen> {
  final List<Map<String, dynamic>> _plans = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.c.api.getMap('/v1/care-plans');
      if (res['plans'] is List) {
        setState(() {
          _plans.clear();
          _plans.addAll(List<Map<String, dynamic>>.from(res['plans']));
        });
      }
    } catch (_) {
      // Offline fallback mock data
      if (_plans.isEmpty) {
        _plans.addAll([
          {
            'id': 'plan-1',
            'title': 'خطة علاج وريدي ومحاليل',
            'frequency': 'يومي',
            'total_occurrences': 7,
            'completed_occurrences': 3,
            'status': 'ACTIVE',
            'next_occurrence_at': DateTime.now().add(const Duration(hours: 18)).toIso8601String(),
          },
          {
            'id': 'plan-2',
            'title': 'متابعة سكر الدم وضغط الدم',
            'frequency': '3 مرات أسبوعياً',
            'total_occurrences': 12,
            'completed_occurrences': 12,
            'status': 'COMPLETED',
          },
        ]);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AeroColors.lightCanvas,
        appBar: AppBar(
          title: Text(
            'خطط الرعاية التمريضية المستمرة',
            style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: const IconThemeData(color: AeroColors.primaryNavy),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
            : _plans.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 48, color: AeroColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد خطط رعاية متكررة حالياً',
                          style: aeroText(size: 14, color: AeroColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _plans.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final p = _plans[index];
                      return AeroCarePlanCard(
                        title: p['title'] ?? 'خطة رعاية',
                        frequency: p['frequency'] ?? 'أسبوعي',
                        totalVisits: p['total_occurrences'] ?? 0,
                        completedVisits: p['completed_occurrences'] ?? 0,
                        status: p['status'] ?? 'ACTIVE',
                        nextVisitAt: p['next_occurrence_at'] != null ? DateTime.tryParse(p['next_occurrence_at']) : null,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تفاصيل الخطة: ${p['title']}')),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}
