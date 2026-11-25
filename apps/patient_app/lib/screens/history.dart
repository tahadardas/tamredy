import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';
import 'commitment.dart';
import 'track.dart';

enum _RequestTab { active, upcoming, past, bills }

/// Unified Request Center — P09 + Active / Upcoming / Past / Unpaid Bills.
class HistoryScreen extends StatefulWidget {
  final PatientController c;
  final TamBottomNav nav;
  const HistoryScreen({super.key, required this.c, required this.nav});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late _RequestTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.c.stage != VisitStage.none
        ? _RequestTab.active
        : _RequestTab.past;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tc = context.tamColors;

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final hasActive = c.stage != VisitStage.none;
        final upcoming = c.history
            .where((h) => h.status.contains('مجدول') || h.status.contains('قادم'))
            .toList();
        final past = c.history
            .where((h) => !h.status.contains('مجدول') && !h.status.contains('قادم'))
            .toList();
        final unpaidBills = c.history
            .where((h) =>
                h.requestId != null &&
                (h.status.contains('بانتظار الدفع') ||
                    h.status.contains('جزئي') ||
                    h.status == 'مكتملة'))
            .toList();

        return Scaffold(
          backgroundColor: tc.background,
          bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom == 0
              ? widget.nav
              : null,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: tc.surface,
                    border: Border(bottom: BorderSide(color: tc.border)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Image.asset(
                            'assets/images/logo_mark.png',
                            package: kFontPackage,
                            width: 30,
                            height: 30,
                            excludeFromSemantics: true,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'مركز طلباتي',
                              style: TamTypography.sectionTitle(
                                color: tc.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _TabPill(
                              label: hasActive ? 'الحالية (1)' : 'الحالية',
                              selected: _tab == _RequestTab.active,
                              onTap: () => setState(() => _tab = _RequestTab.active),
                            ),
                            const SizedBox(width: 8),
                            _TabPill(
                              label: 'القادمة (${upcoming.length})',
                              selected: _tab == _RequestTab.upcoming,
                              onTap: () => setState(() => _tab = _RequestTab.upcoming),
                            ),
                            const SizedBox(width: 8),
                            _TabPill(
                              label: 'السابقة (${past.length})',
                              selected: _tab == _RequestTab.past,
                              onTap: () => setState(() => _tab = _RequestTab.past),
                            ),
                            const SizedBox(width: 8),
                            _TabPill(
                              label: 'الفواتير (${unpaidBills.length})',
                              selected: _tab == _RequestTab.bills,
                              onTap: () => setState(() => _tab = _RequestTab.bills),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _tab == _RequestTab.active && hasActive
                      ? TrackScreen(c: c, nav: widget.nav, embedded: true)
                      : RefreshIndicator(
                          color: tc.primary,
                          onRefresh: kDemoMode ? () async {} : c.loadHistory,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                            children: [
                              if (c.historyError != null)
                                TamErrorState(
                                  title: 'تعذر تحميل سجل الطلبات',
                                  message: c.historyError!,
                                  onRetry: c.loadHistory,
                                ),
                              if (_tab == _RequestTab.active && !hasActive)
                                TamEmptyState(
                                  icon: Icons.medical_services_outlined,
                                  title: 'لا يوجد طلب نشط حالياً',
                                  message:
                                      'يمكنك طلب زيارة تمريضية جديدة من الرئيسية في أي وقت.',
                                  actionLabel: 'طلب زيارة جديدة',
                                  onAction: () => c.setTab(0),
                                ),
                              if (_tab == _RequestTab.upcoming)
                                _buildHistoryList(
                                  context,
                                  upcoming,
                                  emptyTitle: 'لا توجد زيارات مجدولة قادمة',
                                  emptyMsg:
                                      'الزيارات التي تحجزها بموعد مسبق ستظهر هنا.',
                                ),
                              if (_tab == _RequestTab.past)
                                _buildHistoryList(
                                  context,
                                  past,
                                  emptyTitle: 'لا توجد طلبات سابقة بعد',
                                  emptyMsg:
                                      'ستظهر طلباتك المكتملة والملغاة هنا مع تفاصيل الفاتورة.',
                                ),
                              if (_tab == _RequestTab.bills)
                                _buildHistoryList(
                                  context,
                                  unpaidBills,
                                  emptyTitle: 'لا توجد فواتير مسجلة',
                                  emptyMsg:
                                      'فواتير الزيارات المكتملة والمستحقة ستظهر هنا.',
                                ),
                              const SectionTitle('خيارات إضافية'),
                              SoftButton(
                                'سجل الالتزام بالمواعيد',
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => CommitmentScreen(api: c.api),
                                  ),
                                ),
                              ),
                              TamCard(
                                child: ListRow(
                                  icon: Icons.add_circle_outline_rounded,
                                  title: 'تكرار طلب سابق',
                                  subtitle: 'العودة لاختيار خدمة تمريضية جديدة',
                                  trailing: Icon(
                                    Icons.chevron_left_rounded,
                                    color: tc.textSecondary,
                                  ),
                                  divider: false,
                                  onTap: () => c.setTab(0),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryList(
    BuildContext context,
    List<HistoryItem> items, {
    required String emptyTitle,
    required String emptyMsg,
  }) {
    if (items.isEmpty) {
      return TamEmptyState(
        icon: Icons.calendar_today_outlined,
        title: emptyTitle,
        message: emptyMsg,
      );
    }
    return TamCard(
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            ListRow(
              icon: items[i].status == 'ملغاة'
                  ? Icons.cancel_outlined
                  : Icons.check_circle_outline_rounded,
              tone: items[i].status == 'ملغاة' ? Tone.danger : Tone.teal,
              title: items[i].title,
              subtitle: items[i].price > 0
                  ? '${items[i].date} • ${formatMoney(items[i].price)}'
                  : items[i].date,
              trailing: TamStatusBadge(
                labelOverride: items[i].status,
                compact: true,
              ),
              divider: i != items.length - 1,
              onTap: items[i].requestId != null
                  ? () => _showBill(context, items[i].requestId!)
                  : null,
            ),
        ],
      ),
    );
  }

  Future<void> _showBill(BuildContext context, String requestId) async {
    final bill = widget.c.api
        .getMap('/v1/requests/$requestId/bill')
        .then(BillInfo.fromJson);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<BillInfo>(
            future: bill,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const NoticeBox('تعذر تحميل الفاتورة. حاول مجددًا.');
              }
              if (!snapshot.hasData) {
                return const LinearProgressIndicator();
              }
              return BillCard(bill: snapshot.data!);
            },
          ),
        ),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: tc.primaryTint,
      backgroundColor: tc.surfaceElevated,
      labelStyle: aeroText(
        size: 13,
        weight: selected ? FontWeight.w700 : FontWeight.w600,
        color: selected ? tc.primaryDark : tc.textSecondary,
      ),
      side: BorderSide(color: selected ? tc.primary : tc.border),
    );
  }
}
