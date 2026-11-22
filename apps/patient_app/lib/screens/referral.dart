import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

/// Personal referral code: share it with friends; a new user can also enter a friend's code once.
class ReferralCard extends StatefulWidget {
  final PatientController c;
  const ReferralCard({super.key, required this.c});
  @override
  State<ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<ReferralCard> {
  final _friend = TextEditingController();
  String? _msg;

  @override
  void initState() {
    super.initState();
    widget.c.loadReferral();
  }

  @override
  void dispose() {
    _friend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.c,
    builder: (context, _) {
      final r = widget.c.referral;
      if (r == null || r['enabled'] != true) return const SizedBox.shrink();
      return TamCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ادعُ أصدقاءك',
              style: tamText(
                size: 16,
                weight: FontWeight.w800,
                color: TamreedyColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'صديقك يحصل على خصم ${r['friendGets']}% على أول طلب، وأنت تحصل على خصم ${r['youGet']}% بعد أول طلب مدفوع له.',
              style: tamText(
                size: 12,
                color: TamreedyColors.subtext,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: TamreedyColors.tealTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${r['code']}',
                      textDirection: TextDirection.ltr,
                      style: tamText(
                        size: 20,
                        weight: FontWeight.w800,
                        color: TamreedyColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: TamreedyColors.teal),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: '${r['code']}'));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم نسخ الكود')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'دعوتَ ${r['invited']} • مكافآت حصلتَ عليها ${r['rewarded']}',
              style: tamText(size: 11.5, color: TamreedyColors.subtext),
            ),
            if (r['alreadyReferred'] != true) ...[
              const Divider(height: 24, color: TamreedyColors.border),
              Text(
                'هل دعاك صديق؟ أدخل كوده',
                style: tamText(
                  size: 13,
                  weight: FontWeight.w700,
                  color: TamreedyColors.navy,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: TamreedyColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _friend,
                        textCapitalization: TextCapitalization.characters,
                        textDirection: TextDirection.ltr,
                        style: tamText(size: 14, weight: FontWeight.w700),
                        decoration: InputDecoration(
                          hintText: 'كود الصديق',
                          hintStyle: tamText(
                            size: 13,
                            color: TamreedyColors.subtext,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: TamreedyColors.teal,
                      ),
                      onPressed: () async {
                        final m = await widget.c.claimReferral(_friend.text);
                        if (mounted) setState(() => _msg = m);
                      },
                      child: Text(
                        'تطبيق',
                        style: tamText(
                          size: 13,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _msg!,
                    style: tamText(
                      size: 12,
                      weight: FontWeight.w700,
                      color: TamreedyColors.success,
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
