import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';

class ReferralScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const ReferralScreen({super.key, required this.session});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  final _friendCodeCtrl = TextEditingController();
  String? _claimMessage;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    widget.session.finance.loadReferral();
  }

  @override
  void dispose() {
    _friendCodeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final finance = widget.session.finance;

    return TamScaffold(
      title: 'برنامج دعوة الأصدقاء',
      subtitle: 'شارك رمز دعوتك واستفد من خصومات الزيارات',
      showBack: true,
      onRefresh: finance.loadReferral,
      children: [
        ListenableBuilder(
          listenable: finance,
          builder: (context, _) {
            final info = finance.referralInfo;
            if (finance.loadingReferral && info == null) {
              return const TamSkeleton.card(height: 150);
            }
            final code = '${info?['code'] ?? '—'}';
            final alreadyReferred = info?['alreadyReferred'] == true;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('رمز الدعوة الخاص بك', style: aeroText(size: 14, color: tc.textSecondary)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              code,
                              style: aeroText(size: 24, weight: FontWeight.w800, color: tc.primary),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: code == '—'
                                ? null
                                : () {
                                    Clipboard.setData(ClipboardData(text: code));
                                    TamToast.show(context, 'تم نسخ رمز الدعوة', tone: TamToastTone.success);
                                  },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('نسخ'),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      KeyValueRow('الأصدقاء المدعوون', '${info?['invited'] ?? 0}'),
                      KeyValueRow('المكافآت المكتسبة', '${info?['rewarded'] ?? 0}'),
                    ],
                  ),
                ),
                if (!alreadyReferred)
                  TamCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('هل لديك رمز دعوة من صديق؟', style: aeroText(size: 14.5, weight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _friendCodeCtrl,
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(
                                  hintText: 'أدخل رمز الدعوة',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _claiming
                                  ? null
                                  : () async {
                                      setState(() => _claiming = true);
                                      try {
                                        final msg = await finance.claimReferralCode(_friendCodeCtrl.text);
                                        if (mounted) setState(() => _claimMessage = msg);
                                      } catch (e) {
                                        if (mounted) setState(() => _claimMessage = explainError(e));
                                      } finally {
                                        if (mounted) setState(() => _claiming = false);
                                      }
                                    },
                              child: Text(_claiming ? '...' : 'تطبيق'),
                            ),
                          ],
                        ),
                        if (_claimMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(_claimMessage!, style: aeroText(size: 12.5, color: tc.primary)),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
