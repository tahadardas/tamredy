import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../app/patient_router.dart';
import '../../core/patient_session_coordinator.dart';
import '../profile/commitment_screen.dart';

enum _RequestsSection { active, upcoming, past, bills }

class RequestsCenterScreen extends StatefulWidget {
  final PatientSessionCoordinator session;

  const RequestsCenterScreen({super.key, required this.session});

  @override
  State<RequestsCenterScreen> createState() => _RequestsCenterScreenState();
}

class _RequestsCenterScreenState extends State<RequestsCenterScreen> {
  _RequestsSection _section = _RequestsSection.active;

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final store = widget.session.requests;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = store.activeRequests;
        final upcoming = store.upcomingRequests;
        final past = store.pastRequests;
        final bills = store.unpaidBills;

        final shown = switch (_section) {
          _RequestsSection.active => active,
          _RequestsSection.upcoming => upcoming,
          _RequestsSection.past => past,
          _RequestsSection.bills => bills,
        };

        return Scaffold(
          backgroundColor: tc.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Container(
                  color: tc.surface,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'مركز طلباتي',
                              style: aeroText(size: 18, weight: FontWeight.w800, color: tc.textPrimary),
                            ),
                          ),
                          IconButton(
                            tooltip: 'سجل الالتزام بالمواعيد',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => CommitmentScreen(api: widget.session.api),
                              ),
                            ),
                            icon: Icon(Icons.verified_outlined, color: tc.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _Pill(
                              label: active.isEmpty ? 'الحالية' : 'الحالية (${active.length})',
                              selected: _section == _RequestsSection.active,
                              onTap: () => setState(() => _section = _RequestsSection.active),
                            ),
                            const SizedBox(width: 8),
                            _Pill(
                              label: upcoming.isEmpty ? 'القادمة' : 'القادمة (${upcoming.length})',
                              selected: _section == _RequestsSection.upcoming,
                              onTap: () => setState(() => _section = _RequestsSection.upcoming),
                            ),
                            const SizedBox(width: 8),
                            _Pill(
                              label: bills.isEmpty ? 'المستحقة' : 'المستحقة (${bills.length})',
                              selected: _section == _RequestsSection.bills,
                              onTap: () => setState(() => _section = _RequestsSection.bills),
                            ),
                            const SizedBox(width: 8),
                            _Pill(
                              label: 'السابقة',
                              selected: _section == _RequestsSection.past,
                              onTap: () => setState(() => _section = _RequestsSection.past),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => store.refreshAll(),
                    child: store.loading && store.allRequests.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(16),
                            children: const [
                              TamSkeleton.card(height: 110),
                              SizedBox(height: 10),
                              TamSkeleton.card(height: 110),
                            ],
                          )
                        : store.error != null && store.allRequests.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  TamErrorState(
                                    title: 'تعذر تحميل الطلبات',
                                    message: store.error!,
                                    onRetry: () => store.refreshAll(),
                                  ),
                                ],
                              )
                            : shown.isEmpty
                                ? ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      TamEmptyState(
                                        icon: Icons.assignment_outlined,
                                        title: switch (_section) {
                                          _RequestsSection.active => 'لا توجد طلبات نشطة حالياً',
                                          _RequestsSection.upcoming => 'لا توجد مواعيد مجدولة',
                                          _RequestsSection.bills => 'لا توجد فواتير مستحقة',
                                          _RequestsSection.past => 'لا توجد زيارات سابقة',
                                        },
                                        message: 'عند إنشاء طلب جديد ستتمكن من متابعة حالته لحظة بلحظة من هنا.',
                                      ),
                                      if (_section == _RequestsSection.active) ...[
                                        const SizedBox(height: 12),
                                        PrimaryButton(
                                          'طلب ممرض الآن',
                                          onPressed: () =>
                                              PatientRouter.openServiceCatalog(context, widget.session),
                                        ),
                                      ],
                                    ],
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: shown.length,
                                    itemBuilder: (context, idx) {
                                      final req = shown[idx];
                                      return _RequestSummaryCard(
                                        req: req,
                                        onTap: () => PatientRouter.openRequestSmart(
                                          context,
                                          widget.session,
                                          req,
                                        ),
                                      );
                                    },
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
}

class _Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return ChoiceChip(
      label: Text(
        label,
        style: aeroText(
          size: 12.5,
          weight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? Colors.white : tc.textPrimary,
        ),
      ),
      selected: selected,
      selectedColor: tc.primary,
      backgroundColor: tc.background,
      onSelected: (_) => onTap(),
    );
  }
}

class _RequestSummaryCard extends StatelessWidget {
  final TypedCareRequest req;
  final VoidCallback onTap;

  const _RequestSummaryCard({required this.req, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final title = req.serviceTitle.isNotEmpty ? req.serviceTitle : 'زيارة تمريضية';
    final dateText = (req.scheduledAt ?? req.createdAt)?.toLocal().toString().split('.').first ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: tc.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tc.border),
        boxShadow: tc.cardShadow,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary),
                    ),
                  ),
                  TamStatusBadge(status: req.status, compact: true),
                ],
              ),
              if (req.beneficiaryName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'المستفيد: ${req.beneficiaryName}',
                  style: aeroText(size: 12.5, color: tc.textSecondary),
                ),
              ],
              if (req.nurseName != null && req.nurseName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'الممرض: ${req.nurseName}',
                  style: aeroText(size: 12.5, weight: FontWeight.w700, color: tc.primary),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dateText,
                      style: aeroText(size: 11.5, color: tc.textSecondary),
                    ),
                  ),
                  Text(
                    formatMoney(req.amountDue ?? req.priceAmount),
                    style: aeroText(size: 14, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
