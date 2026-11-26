import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';

class VisitRatingScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String visitId;

  const VisitRatingScreen({
    super.key,
    required this.session,
    required this.visitId,
  });

  @override
  State<VisitRatingScreen> createState() => _VisitRatingScreenState();
}

class _VisitRatingScreenState extends State<VisitRatingScreen> {
  int _overall = 0;
  int _punctuality = 0;
  int _clinical = 0;
  int _conduct = 0;
  final _commentCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_overall <= 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.session.finance.submitReview(
        visitId: widget.visitId,
        overallStars: _overall,
        punctualityStars: _punctuality,
        clinicalStars: _clinical,
        conductStars: _conduct,
        comment: _commentCtrl.text,
      );
      await widget.session.requests.refreshAll(silent: true);
      if (!mounted) return;
      TamToast.show(context, 'شكراً لك! تم حفظ تقييمك بنجاح.', tone: TamToastTone.success);
      PatientRouter.switchTab(0);
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _starRow(String label, int current, ValueChanged<int> onChanged) {
    final tc = context.tamColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: aeroText(size: 13.5, weight: FontWeight.w700, color: tc.textPrimary)),
          ),
          for (var i = 1; i <= 5; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: _submitting ? null : () => onChanged(i),
              icon: Icon(
                i <= current ? Icons.star_rounded : Icons.star_outline_rounded,
                color: i <= current ? const Color(0xFFF59E0B) : tc.borderStrong,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamScaffold(
      title: 'تقييم الزيارة',
      subtitle: 'تقييمك يساهم في رفع جودة الرعاية المنزلية',
      showBack: true,
      children: [
        TamCard(
          child: Column(
            children: [
              Icon(Icons.verified_outlined, size: 42, color: tc.primary),
              const SizedBox(height: 10),
              Text('كيف كانت تجربتك مع الزيارة؟', style: aeroText(size: 16.5, weight: FontWeight.w800)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      iconSize: 36,
                      onPressed: _submitting ? null : () => setState(() => _overall = i),
                      icon: Icon(
                        i <= _overall ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: i <= _overall ? const Color(0xFFF59E0B) : tc.borderStrong,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        TamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('تقييم المعايير التفصيلية (اختياري)', style: aeroText(size: 14, weight: FontWeight.w800)),
              const SizedBox(height: 6),
              _starRow('الالتزام بالموعد', _punctuality, (v) => setState(() => _punctuality = v)),
              _starRow('المهارة السريرية والتعقيم', _clinical, (v) => setState(() => _clinical = v)),
              _starRow('الاحترام والتواصل', _conduct, (v) => setState(() => _conduct = v)),
              const SizedBox(height: 10),
              TextField(
                controller: _commentCtrl,
                maxLines: 3,
                enabled: !_submitting,
                decoration: InputDecoration(
                  labelText: 'ملاحظات إضافية (اختياري)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
        AeroButton(
          _submitting ? 'جارٍ الإرسال...' : 'إرسال التقييم',
          isLoading: _submitting,
          onPressed: (_overall <= 0 || _submitting) ? null : _submit,
        ),
      ],
    );
  }
}
