import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

class MarketplaceScreen extends StatefulWidget {
  final NurseSessionCoordinator session;

  const MarketplaceScreen({super.key, required this.session});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  int _subTab = 0; // 0: available, 1: my proposals, 2: visit history
  String _sortBy = 'nearest';
  bool _onlySaved = false;

  Future<void> _openSubmitProposalSheet(Map<String, dynamic> req) async {
    final reqId = '${req['id'] ?? ''}';
    final noteCtrl = TextEditingController();
    int selectedMins = 20;
    bool sending = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.viewInsetsOf(ctx).bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تقديم عرض جاهزية',
                  style: aeroText(size: 17, weight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${req['service_title'] ?? 'زيارة تمريضية'} • ${req['approximate_area'] ?? ''}',
                  style: aeroText(size: 13, color: context.tamColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Text('الوقت المتوقع للوصول', style: aeroText(size: 13.5, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final mins in const [15, 20, 30, 45, 60])
                      ChoiceChip(
                        label: Text('$mins دقيقة'),
                        selected: selectedMins == mins,
                        onSelected: (_) => setSheet(() => selectedMins = mins),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة للمريض (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                AeroButton(
                  sending ? 'جارٍ إرسال العرض...' : 'إرسال العرض الآن',
                  isLoading: sending,
                  onPressed: sending
                      ? null
                      : () async {
                          setSheet(() => sending = true);
                          try {
                            await widget.session.marketplace.submitProposal(
                              reqId,
                              estimatedMinutes: selectedMins,
                              note: noteCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              TamToast.show(context, 'تم إرسال عرض الجاهزية بنجاح', tone: TamToastTone.success);
                            }
                          } catch (e) {
                            setSheet(() => sending = false);
                            if (ctx.mounted) {
                              TamToast.show(ctx, explainError(e, fallback: 'تعذر إرسال العرض'), tone: TamToastTone.error);
                            }
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    noteCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final store = widget.session.marketplace;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Container(
            color: tc.surface,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('سوق الطلبات والعروض',
                    style: aeroText(size: 18, weight: FontWeight.w800, color: tc.textPrimary)),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('المتاحة')),
                    ButtonSegment(value: 1, label: Text('عروضي')),
                    ButtonSegment(value: 2, label: Text('سجلي')),
                  ],
                  selected: {_subTab},
                  onSelectionChanged: (s) => setState(() => _subTab = s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) {
                if (store.loading && store.requests.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: const [TamSkeleton.card(height: 120), SizedBox(height: 10), TamSkeleton.card(height: 120)],
                  );
                }

                if (_subTab == 1) {
                  return RefreshIndicator(
                    onRefresh: () => store.refreshAll(),
                    child: store.myProposals.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: const [
                              TamEmptyState(
                                icon: Icons.outbox_outlined,
                                title: 'لم تقدم عروضاً بعد',
                                message: 'اختر أي طلب مفتوح لتقديم وقت الوصول المقترح.',
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: store.myProposals.length,
                            itemBuilder: (context, idx) {
                              final p = store.myProposals[idx];
                              final status = '${p['status'] ?? ''}';
                              final id = '${p['id'] ?? ''}';
                              return TamCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text('${p['service_title'] ?? 'عرض مقدم'}',
                                              style: aeroText(size: 15, weight: FontWeight.w800)),
                                        ),
                                        TamStatusBadge(status: status, compact: true),
                                      ],
                                    ),
                                    if (status == 'PENDING') ...[
                                      const SizedBox(height: 8),
                                      OutlinedButton(
                                        onPressed: () => store.withdrawProposal(id),
                                        child: const Text('سحب العرض'),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  );
                }

                if (_subTab == 2) {
                  return RefreshIndicator(
                    onRefresh: () => store.refreshAll(),
                    child: store.completedHistory.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: const [
                              TamEmptyState(
                                icon: Icons.history_rounded,
                                title: 'لا يوجد سجل زيارات مكتملة',
                                message: 'ستظهر الزيارات التي أتممتها وحصتك منها هنا.',
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: store.completedHistory.length,
                            itemBuilder: (context, idx) {
                              final h = store.completedHistory[idx];
                              return TamCard(
                                child: KeyValueRow(
                                  '${h['service_title'] ?? 'زيارة'}',
                                  formatMoney((num.tryParse('${h['nurse_earning'] ?? h['price_amount'] ?? 0}') ?? 0).round()),
                                ),
                              );
                            },
                          ),
                  );
                }

                var shown = List<Map<String, dynamic>>.from(store.requests);
                if (_onlySaved) {
                  shown = shown.where((r) => r['is_saved'] == true).toList();
                }
                if (_sortBy == 'pay') {
                  shown.sort((a, b) => (num.tryParse('${b['estimated_nurse_earning'] ?? 0}') ?? 0)
                      .compareTo(num.tryParse('${a['estimated_nurse_earning'] ?? 0}') ?? 0));
                }

                return RefreshIndicator(
                  onRefresh: () => store.refreshAll(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('كل المسافات'),
                              selected: store.maxDistanceKm == null,
                              onSelected: (_) => store.setMaxDistance(null),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('حتى 5 كم'),
                              selected: store.maxDistanceKm == 5,
                              onSelected: (_) => store.setMaxDistance(5),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('حتى 10 كم'),
                              selected: store.maxDistanceKm == 10,
                              onSelected: (_) => store.setMaxDistance(10),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('الأقرب'),
                              selected: _sortBy == 'nearest',
                              onSelected: (_) => setState(() => _sortBy = 'nearest'),
                            ),
                            const SizedBox(width: 6),
                            ChoiceChip(
                              label: const Text('الأعلى أجراً'),
                              selected: _sortBy == 'pay',
                              onSelected: (_) => setState(() => _sortBy = 'pay'),
                            ),
                            const SizedBox(width: 6),
                            FilterChip(
                              label: const Text('المحفوظة'),
                              selected: _onlySaved,
                              onSelected: (v) => setState(() => _onlySaved = v),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (store.error != null)
                        TamErrorState(
                          title: 'تعذر تحميل السوق المفتوح',
                          message: store.error!,
                          onRetry: () => store.refreshAll(),
                        )
                      else if (shown.isEmpty)
                        const TamEmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'لا توجد طلبات مطابقة الآن',
                          message: 'اسحب للتحديث لعرض أحدث الطلبات المفتوحة في منطقتك.',
                        )
                      else
                        for (final req in shown)
                          Builder(builder: (context) {
                            final id = '${req['id'] ?? ''}';
                            final saved = req['is_saved'] == true;
                            final dist = (num.tryParse('${req['distance_km'] ?? 0}') ?? 0).toDouble();
                            final share = (num.tryParse('${req['estimated_nurse_earning'] ?? req['net_earnings'] ?? 0}') ?? 0).round();
                            return TamCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${req['service_title'] ?? 'زيارة تمريضية'}',
                                          style: aeroText(size: 15, weight: FontWeight.w800),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: saved ? 'إزالة من المحفوظة' : 'حفظ',
                                        onPressed: () => store.toggleSave(id, saved),
                                        icon: Icon(
                                          saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                          color: tc.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${req['approximate_area'] ?? 'دمشق'} • ${dist.toStringAsFixed(1)} كم',
                                    style: aeroText(size: 12.5, color: tc.textSecondary),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'حصتك: ${formatMoney(share)}',
                                          style: aeroText(size: 14, weight: FontWeight.w800, color: tc.primary),
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => _openSubmitProposalSheet(req),
                                        child: const Text('تقديم عرض'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
