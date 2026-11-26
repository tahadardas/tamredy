import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

class PostVisitReportScreen extends StatefulWidget {
  final NurseSessionCoordinator session;

  const PostVisitReportScreen({super.key, required this.session});

  @override
  State<PostVisitReportScreen> createState() => _PostVisitReportScreenState();
}

class _PostVisitReportScreenState extends State<PostVisitReportScreen> {
  int _stars = 5;
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return TamScaffold(
      title: 'تقرير ما بعد الزيارة',
      subtitle: 'تقييم داخلي لتجربة الزيارة (غير ظاهر للمريض)',
      showBack: true,
      children: [
        TamCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('تقييم التعامل والبيئة المنزلية', style: aeroText(size: 15, weight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      onPressed: _saving ? null : () => setState(() => _stars = i),
                      icon: Icon(
                        i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 32,
                        color: i <= _stars ? const Color(0xFFF59E0B) : tc.borderStrong,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                maxLines: 3,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات مهنية داخلية (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        AeroButton(
          _saving ? 'جارٍ الإرسال...' : 'حفظ التقرير',
          isLoading: _saving,
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.session.visit.submitPostVisitReport(
                      stars: _stars,
                      note: _noteCtrl.text,
                    );
                    if (!context.mounted) return;
                    TamToast.show(context, 'تم حفظ التقرير بنجاح', tone: TamToastTone.success);
                    Navigator.of(context).pop();
                  } catch (e) {
                    if (context.mounted) {
                      TamToast.show(context, explainError(e), tone: TamToastTone.error);
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
        ),
      ],
    );
  }
}
