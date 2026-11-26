import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

class NurseCalendarScreen extends StatefulWidget {
  final NurseSessionCoordinator session;

  const NurseCalendarScreen({super.key, required this.session});

  @override
  State<NurseCalendarScreen> createState() => _NurseCalendarScreenState();
}

class _NurseCalendarScreenState extends State<NurseCalendarScreen> {
  Future<void> _addBusyBlock() async {
    final reasonCtrl = TextEditingController();
    int hours = 2;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('تسجيل وقت انشغال شخصي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'السبب (اختياري)'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: hours,
                decoration: const InputDecoration(labelText: 'المدة بدءاً من الآن'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('ساعة واحدة')),
                  DropdownMenuItem(value: 2, child: Text('ساعتان')),
                  DropdownMenuItem(value: 4, child: Text('4 ساعات')),
                  DropdownMenuItem(value: 8, child: Text('8 ساعات')),
                ],
                onChanged: (v) => setDlg(() => hours = v ?? 2),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDlg(() => saving = true);
                      try {
                        final start = DateTime.now();
                        await widget.session.calendar.addBusyBlock(
                          start: start,
                          end: start.add(Duration(hours: hours)),
                          reason: reasonCtrl.text,
                        );
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        setDlg(() => saving = false);
                        if (ctx.mounted) TamToast.show(ctx, explainError(e), tone: TamToastTone.error);
                      }
                    },
              child: Text(saving ? 'جارٍ الحفظ...' : 'حفظ الحظر'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final store = widget.session.calendar;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Container(
            color: tc.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'جدول المواعيد والأوقات',
                    style: aeroText(size: 18, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addBusyBlock,
                  icon: const Icon(Icons.block_rounded, size: 17),
                  label: const Text('انشغال شخصي'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => RefreshIndicator(
                onRefresh: store.load,
                child: store.loading && store.items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [TamSkeleton.card(height: 110)],
                      )
                    : store.error != null && store.items.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              TamErrorState(
                                title: 'تعذر تحميل الجدول',
                                message: store.error!,
                                onRetry: store.load,
                              ),
                            ],
                          )
                        : store.items.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.all(16),
                                children: const [
                                  TamEmptyState(
                                    icon: Icons.event_available_outlined,
                                    title: 'لا توجد مواعيد محجوزة للأيام السبعة القادمة',
                                    message: 'تظهر هنا الزيارات المجدولة المؤكدة وأوقات عدم التفرغ الشخصية.',
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: store.items.length,
                                itemBuilder: (context, idx) {
                                  final item = store.items[idx];
                                  final isBusyBlock = item['block_type'] == 'BUSY_PERSONAL';
                                  final startDt = DateTime.tryParse('${item['start_time'] ?? ''}')?.toLocal();
                                  return TamCard(
                                    child: ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        isBusyBlock ? Icons.block_rounded : Icons.event_note_rounded,
                                        color: isBusyBlock ? tc.warning : tc.primary,
                                      ),
                                      title: Text('${item['title'] ?? 'موعد'}',
                                          style: aeroText(size: 14.5, weight: FontWeight.w800)),
                                      subtitle: Text(
                                        startDt == null
                                            ? '—'
                                            : '${MaterialLocalizations.of(context).formatMediumDate(startDt)} • ${TimeOfDay.fromDateTime(startDt).format(context)}',
                                        style: aeroText(size: 12.5, color: tc.textSecondary),
                                      ),
                                      trailing: isBusyBlock
                                          ? IconButton(
                                              tooltip: 'حذف الانشغال',
                                              icon: Icon(Icons.delete_outline, color: tc.danger),
                                              onPressed: () => store.deleteBlock('${item['id']}'),
                                            )
                                          : null,
                                    ),
                                  );
                                },
                              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
