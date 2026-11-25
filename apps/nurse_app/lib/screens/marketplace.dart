import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class NurseMarketplaceScreen extends StatefulWidget {
  final NurseController c;
  final TamBottomNav nav;

  const NurseMarketplaceScreen({super.key, required this.c, required this.nav});

  @override
  State<NurseMarketplaceScreen> createState() => _NurseMarketplaceScreenState();
}

class _NurseMarketplaceScreenState extends State<NurseMarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchCtrl = TextEditingController();
  double? _maxDistanceFilter;
  String _sortBy = 'nearest'; // 'nearest' | 'pay'
  bool _onlySaved = false;
  final Set<String> _savedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    widget.c.loadMarketplaceRequests();
    widget.c.loadMyProposals();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _openProposalSheet(Map<String, dynamic> req) {
    final reqId = req['id']?.toString() ?? '';
    final serviceTitle = req['service_title']?.toString() ?? 'خدمة تمريضية';
    final approximateArea = req['approximate_area']?.toString() ?? 'دمشق';
    final distanceKm = (num.tryParse('${req['distance_km']}') ?? 0.0).toDouble();
    final netEarnings = (num.tryParse('${req['estimated_nurse_earning'] ?? req['net_earnings']}') ?? 0).round();

    showAeroModalBottomSheet(
      context: context,
      builder: (_) => AeroProposalSubmissionSheet(
        requestId: reqId,
        serviceTitle: serviceTitle,
        approximateArea: approximateArea,
        distanceKm: distanceKm,
        netEarnings: netEarnings,
        onSubmit: (estimatedMinutes, specificTime, note) async {
          final messenger = ScaffoldMessenger.of(context);
          final ok = await widget.c.submitProposal(
            reqId,
            estimatedMinutes: estimatedMinutes,
            specificTime: specificTime,
            note: note,
          );
          if (!mounted) return;
          if (ok) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('تم إرسال عرض الجاهزية بنجاح إلى المريض!'),
                backgroundColor: AeroColors.success,
              ),
            );
            _tabController.animateTo(1); // Switch to My Proposals tab
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(widget.c.error ?? 'تعذر إرسال عرض الجاهزية'),
                backgroundColor: AeroColors.danger,
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
        title: Text(
          'سوق الطلبات والزيارات',
          style: aeroText(size: 17, weight: FontWeight.w700, color: tc.textPrimary),
        ),
        backgroundColor: tc.surface,
        elevation: 0,
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: tc.primary,
          unselectedLabelColor: tc.textSecondary,
          indicatorColor: tc.primary,
          indicatorWeight: 3,
          labelStyle: aeroText(size: 13, weight: FontWeight.w700),
          unselectedLabelStyle: aeroText(size: 13, weight: FontWeight.w500),
          tabs: const [
            Tab(text: 'الطلبات المتاحة'),
            Tab(text: 'عروضي المرسلة'),
            Tab(text: 'سجل الزيارات'),
          ],
        ),
      ),
      bottomNavigationBar: MediaQuery.viewInsetsOf(context).bottom == 0
          ? widget.nav
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAvailableRequestsTab(),
          _buildMyProposalsTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildAvailableRequestsTab() {
    final tc = context.tamColors;
    return ListenableBuilder(
      listenable: widget.c,
      builder: (context, _) {
        final c = widget.c;
        if (c.isLoadingMarketplace && c.marketplaceRequests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                TamSkeleton.card(height: 110),
                SizedBox(height: 12),
                TamSkeleton.card(height: 110),
              ],
            ),
          );
        }

        final q = _searchCtrl.text.trim();
        final filtered = c.marketplaceRequests
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((req) {
              if (_onlySaved && !_savedIds.contains('${req['id'] ?? ''}')) {
                return false;
              }
              if (q.isNotEmpty) {
                final title = '${req['service_title'] ?? ''}';
                final area = '${req['approximate_area'] ?? ''}';
                if (!title.contains(q) && !area.contains(q)) return false;
              }
              return true;
            })
            .toList()
          ..sort((a, b) {
            if (_sortBy == 'pay') {
              final payA = num.tryParse('${a['estimated_nurse_earning'] ?? a['net_earnings']}') ?? 0;
              final payB = num.tryParse('${b['estimated_nurse_earning'] ?? b['net_earnings']}') ?? 0;
              return payB.compareTo(payA);
            }
            final distA = num.tryParse('${a['distance_km']}') ?? 999;
            final distB = num.tryParse('${b['distance_km']}') ?? 999;
            return distA.compareTo(distB);
          });

        return RefreshIndicator(
          onRefresh: () => c.loadMarketplaceRequests(maxDistanceKm: _maxDistanceFilter),
          color: tc.primary,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TamSearchField(
                controller: _searchCtrl,
                hint: 'ابحث بالخدمة أو المنطقة...',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: TamSpacing.md),
              // Distance & Sort filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text('الكل', style: aeroText(size: 12, color: _maxDistanceFilter == null ? Colors.white : tc.textPrimary)),
                      selected: _maxDistanceFilter == null,
                      selectedColor: tc.primary,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _maxDistanceFilter = null);
                          c.loadMarketplaceRequests();
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('حتى 5 كم', style: aeroText(size: 12, color: _maxDistanceFilter == 5 ? Colors.white : tc.textPrimary)),
                      selected: _maxDistanceFilter == 5,
                      selectedColor: tc.primary,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _maxDistanceFilter = 5);
                          c.loadMarketplaceRequests(maxDistanceKm: 5);
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('حتى 10 كم', style: aeroText(size: 12, color: _maxDistanceFilter == 10 ? Colors.white : tc.textPrimary)),
                      selected: _maxDistanceFilter == 10,
                      selectedColor: tc.primary,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _maxDistanceFilter = 10);
                          c.loadMarketplaceRequests(maxDistanceKm: 10);
                        }
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: Text('الأقرب', style: aeroText(size: 12, color: _sortBy == 'nearest' ? Colors.white : tc.textPrimary)),
                      selected: _sortBy == 'nearest',
                      selectedColor: tc.secondary,
                      onSelected: (_) => setState(() => _sortBy = 'nearest'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('الأعلى أجراً', style: aeroText(size: 12, color: _sortBy == 'pay' ? Colors.white : tc.textPrimary)),
                      selected: _sortBy == 'pay',
                      selectedColor: tc.secondary,
                      onSelected: (_) => setState(() => _sortBy = 'pay'),
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: Text('المحفوظة', style: aeroText(size: 12, color: _onlySaved ? Colors.white : tc.textPrimary)),
                      selected: _onlySaved,
                      selectedColor: tc.primaryDark,
                      onSelected: (v) => setState(() => _onlySaved = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (c.marketplaceError != null)
                TamErrorState(
                  title: 'تعذر تحميل السوق المفتوح',
                  message: c.marketplaceError!,
                  onRetry: () => c.loadMarketplaceRequests(maxDistanceKm: _maxDistanceFilter),
                )
              else if (filtered.isEmpty)
                const TamEmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'لا توجد طلبات مطابقة حالياً',
                  message:
                      'عند نشر أي طلب رعاية جديد في منطقتك، سيظهر هنا فوراً لتقديم عرض الجاهزية والوقت.',
                )
              else
                for (final req in filtered)
                  _buildMarketplaceRequestCard(req),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMarketplaceRequestCard(Map<String, dynamic> req) {
    final title = req['service_title']?.toString() ?? 'خدمة تمريضية';
    final area = req['approximate_area']?.toString() ?? 'دمشق';
    final dist = (num.tryParse('${req['distance_km']}') ?? 0.0).toDouble();
    final net = (num.tryParse('${req['estimated_nurse_earning'] ?? req['net_earnings']}') ?? 0).round();
    final expMins = (num.tryParse('${req['primary_expected_minutes'] ?? req['expected_minutes']}') ?? 30).toInt();
    final proposalsCount = (num.tryParse('${req['active_proposals_count'] ?? req['proposals_count']}') ?? 0).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AeroRadii.mainCardRadius,
        border: Border.all(color: AeroColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: AeroColors.primaryNavy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AeroColors.aeroTintLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medical_services_outlined, color: AeroColors.accentTeal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: aeroText(size: 15, weight: FontWeight.w700, color: AeroColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$area • نحو ${dist.toStringAsFixed(1)} كم • مدة $expMins دقيقة',
                      style: aeroText(size: 12, color: AeroColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$net ل.س',
                    style: aeroText(size: 15, weight: FontWeight.w800, color: AeroColors.success),
                  ),
                  Text(
                    'صافي الأرباح',
                    style: aeroText(size: 10, color: AeroColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (proposalsCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AeroColors.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$proposalsCount عروض مقدمة',
                    style: aeroText(size: 11, weight: FontWeight.w600, color: AeroColors.primaryNavy),
                  ),
                ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AeroColors.accentTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
                icon: const Icon(Icons.send_rounded, size: 16),
                label: Text(
                  'تقديم عرض جاهزية',
                  style: aeroText(size: 13, weight: FontWeight.w700, color: Colors.white),
                ),
                onPressed: () => _openProposalSheet(req),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyProposalsTab() {
    return ListenableBuilder(
      listenable: widget.c,
      builder: (context, _) {
        final c = widget.c;
        return RefreshIndicator(
          onRefresh: () => c.loadMyProposals(),
          color: AeroColors.accentTeal,
          child: c.myProposals.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.outbox_rounded, size: 48, color: AeroColors.textMuted),
                        const SizedBox(height: 12),
                        Text(
                          'لم تقدم أي عروض بعد',
                          style: aeroText(size: 16, weight: FontWeight.w700, color: AeroColors.primaryNavy),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'العروض التي ترسلها للطلبات المفتوحة ستظهر هنا لمتابعة رد المريض وقبول الزيارة.',
                          textAlign: TextAlign.center,
                          style: aeroText(size: 13, color: AeroColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: c.myProposals.length,
                  itemBuilder: (context, index) {
                    final item = Map<String, dynamic>.from(c.myProposals[index] as Map);
                    final pId = item['id']?.toString() ?? '';
                    final title = item['service_title']?.toString() ?? 'خدمة تمريضية';
                    final area = item['approximate_area']?.toString() ?? 'دمشق';
                    final status = item['status']?.toString() ?? 'PENDING';
                    final arrivalMins = item['estimated_arrival_minutes'] ?? item['estimated_service_minutes'];
                    final net = (num.tryParse('${item['estimated_nurse_earning'] ?? item['net_earnings']}') ?? 0).round();

                    final (statusLabel, statusColor) = switch (status) {
                      'ACCEPTED' => ('تم قبول عرضك!', AeroColors.success),
                      'DECLINED' => ('تم الرفض', AeroColors.danger),
                      'WITHDRAWN' => ('تم السحب', AeroColors.textMuted),
                      'SUPERSEDED' => ('أُسندت لآخر', AeroColors.textMuted),
                      'EXPIRED' => ('منتهي الصلاحية', AeroColors.textMuted),
                      _ => ('قيد المراجعة', AeroColors.warning),
                    };

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AeroRadii.mainCardRadius,
                        border: Border.all(color: AeroColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.textPrimary),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: aeroText(size: 11, weight: FontWeight.w700, color: statusColor),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$area • صافي الأرباح: $net ل.س',
                            style: aeroText(size: 12, color: AeroColors.textSecondary),
                          ),
                          if (arrivalMins != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'التزام الوصول: خلال $arrivalMins دقيقة',
                              style: aeroText(size: 12, weight: FontWeight.w600, color: AeroColors.accentTeal),
                            ),
                          ],
                          if (status == 'PENDING') ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(context);
                                  final ok = await c.withdrawProposal(pId);
                                  if (!mounted) return;
                                  if (ok) {
                                    messenger.showSnackBar(
                                      const SnackBar(content: Text('تم سحب العرض بنجاح')),
                                    );
                                  }
                                },
                                child: Text(
                                  'سحب العرض',
                                  style: aeroText(size: 12, weight: FontWeight.w600, color: AeroColors.danger),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return ListenableBuilder(
      listenable: widget.c,
      builder: (context, _) {
        final c = widget.c;
        if (c.history.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'لا توجد زيارات سابقة مسجلة.',
                style: aeroText(size: 14, color: AeroColors.textSecondary),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: c.history.length,
          itemBuilder: (context, index) {
            final h = c.history[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AeroRadii.mainCardRadius,
                border: Border.all(color: AeroColors.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: AeroColors.success, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.title, style: aeroText(size: 14, weight: FontWeight.w700, color: AeroColors.textPrimary)),
                        Text('${h.date} • منتهية بنجاح', style: aeroText(size: 12, color: AeroColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(
                    formatMoney(h.share),
                    style: aeroText(size: 14, weight: FontWeight.w800, color: AeroColors.primaryNavy),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
