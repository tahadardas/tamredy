import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';

const _relLabels = {
  'SELF': 'نفسي',
  'PARENT': 'الوالد / الوالدة',
  'SPOUSE': 'الزوج / الزوجة',
  'CHILD': 'الابن / الابنة',
  'OTHER': 'قريب آخر',
};

class BeneficiariesScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const BeneficiariesScreen({super.key, required this.session});

  @override
  State<BeneficiariesScreen> createState() => _BeneficiariesScreenState();
}

class _BeneficiariesScreenState extends State<BeneficiariesScreen> {
  @override
  void initState() {
    super.initState();
    widget.session.bookingDraft.loadBeneficiaries();
  }

  Future<void> _add() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String rel = 'PARENT';
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('إضافة مستفيد جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: rel,
                decoration: const InputDecoration(labelText: 'صلة القرابة'),
                items: [
                  for (final e in _relLabels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setDialog(() => rel = v ?? 'OTHER'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الطوارئ (اختياري)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameCtrl.text.trim().length < 2) return;
                      setDialog(() => saving = true);
                      try {
                        await widget.session.bookingDraft.createBeneficiary(
                          displayName: nameCtrl.text,
                          relationship: rel,
                          emergencyContactPhone: phoneCtrl.text,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        setDialog(() => saving = false);
                        if (ctx.mounted) TamToast.show(ctx, explainError(e), tone: TamToastTone.error);
                      }
                    },
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.session.bookingDraft;

    return TamScaffold(
      title: 'المستفيدون',
      subtitle: 'أفراد العائلة المرتبطون بالحساب للزيارات التمريضية',
      showBack: true,
      actions: IconButton(
        tooltip: 'إضافة مستفيد',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_rounded),
      ),
      onRefresh: draft.loadBeneficiaries,
      children: [
        ListenableBuilder(
          listenable: draft,
          builder: (context, _) {
            if (draft.loadingBeneficiaries && draft.beneficiaries.isEmpty) {
              return const TamSkeleton.card(height: 120);
            }
            if (draft.beneficiaries.isEmpty) {
              return Column(
                children: [
                  const TamEmptyState(
                    icon: Icons.people_outline_rounded,
                    title: 'لا يوجد مستفيدون مسجلون',
                    message: 'أضف ملف المستفيد لتسهيل الحجز ومتابعة السجل الصحي.',
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton('إضافة مستفيد جديد', onPressed: _add),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in draft.beneficiaries)
                  TamCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.displayName, style: aeroText(size: 15, weight: FontWeight.w800)),
                              Text(
                                _relLabels[b.relationship] ?? b.relationship,
                                style: aeroText(size: 12.5, color: context.tamColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (b.relationship != 'SELF')
                          IconButton(
                            tooltip: 'إزالة المستفيد',
                            onPressed: () async {
                              try {
                                await draft.removeBeneficiary(b.id);
                              } catch (e) {
                                if (context.mounted) {
                                  TamToast.show(context, explainError(e), tone: TamToastTone.error);
                                }
                              }
                            },
                            icon: Icon(Icons.delete_outline, color: context.tamColors.danger),
                          ),
                      ],
                    ),
                  ),
                PrimaryButton('إضافة مستفيد جديد', onPressed: _add),
              ],
            );
          },
        ),
      ],
    );
  }
}
