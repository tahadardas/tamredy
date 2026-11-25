import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../controller.dart';

class ProposalsViewScreen extends StatefulWidget {
  final PatientController c;

  const ProposalsViewScreen({super.key, required this.c});

  @override
  State<ProposalsViewScreen> createState() => _ProposalsViewScreenState();
}

class _ProposalsViewScreenState extends State<ProposalsViewScreen> {
  List<dynamic> _proposals = [];
  bool _isLoading = true;
  String? _error;
  String? _acceptingProposalId;
  String? _decliningProposalId;

  @override
  void initState() {
    super.initState();
    _fetchProposals();
  }

  Future<void> _fetchProposals() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await widget.c.loadProposals();
      if (mounted) {
        setState(() {
          _proposals = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'تعذر تحميل العروض المقدمة. اسحب للأسفل للتحديث.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _accept(String proposalId) async {
    setState(() => _acceptingProposalId = proposalId);
    try {
      final success = await widget.c.acceptProposal(proposalId);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد الزيارة بنجاح! الممرض في طريقه إليك الآن.'),
            backgroundColor: AeroColors.success,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر قبول العرض: $e'),
            backgroundColor: AeroColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _acceptingProposalId = null);
      }
    }
  }

  Future<void> _decline(String proposalId) async {
    setState(() => _decliningProposalId = proposalId);
    try {
      await widget.c.declineProposal(proposalId);
      await _fetchProposals();
    } catch (_) {
      // silently ignore or notify
    } finally {
      if (mounted) {
        setState(() => _decliningProposalId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    return Scaffold(
      backgroundColor: tc.background,
      appBar: AppBar(
        title: Text(
          'عروض الممرضين الجاهزين',
          style: aeroText(size: 17, weight: FontWeight.w700, color: tc.textPrimary),
        ),
        backgroundColor: tc.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          tooltip: 'رجوع',
          icon: Icon(Icons.arrow_back_rounded, color: tc.textPrimary, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: Icon(Icons.refresh_rounded, color: tc.primary),
            onPressed: _fetchProposals,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchProposals,
        color: AeroColors.accentTeal,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AeroColors.accentTeal))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AeroColors.danger, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: aeroText(size: 14, color: AeroColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          AeroButton(
                            'إعادة المحاولة',
                            onPressed: _fetchProposals,
                          ),
                        ],
                      ),
                    ),
                  )
                : _proposals.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: AeroColors.aeroTintLight,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.hourglass_top_rounded,
                                  size: 40,
                                  color: AeroColors.accentTeal,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'بانتظار أول عرض جاهزية',
                                style: aeroText(
                                  size: 17,
                                  weight: FontWeight.w700,
                                  color: AeroColors.primaryNavy,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'طلبك معروض الآن على الممرضين المؤهلين في منطقتك. ستصلك عروضهم هنا فور تقديمها مع وقت الوصول المتوقع.',
                                textAlign: TextAlign.center,
                                style: aeroText(size: 13, color: AeroColors.textSecondary, height: 1.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _proposals.length,
                        itemBuilder: (context, index) {
                          final item = Map<String, dynamic>.from(_proposals[index] as Map);
                          final pId = item['id']?.toString() ?? '';
                          final arrivalMins = (num.tryParse('${item['estimated_arrival_minutes']}') ?? 0).toInt();
                          final proposedAt = DateTime.tryParse('${item['proposed_arrival_at']}');
                          final rating = (num.tryParse('${item['rating_avg']}') ?? 5.0).toDouble();
                          final visitsCount = (num.tryParse('${item['completed_visits_count']}') ?? 0).toInt();
                          final price = (num.tryParse('${item['price_amount']}') ?? 0).toInt();

                          final proposalData = AeroProposalData(
                            id: pId,
                            nurseId: item['nurse_id']?.toString() ?? '',
                            nurseName: item['full_name']?.toString() ?? 'ممرض معتمد',
                            ratingAvg: rating,
                            completedVisitsCount: visitsCount,
                            estimatedArrivalMinutes: arrivalMins > 0 ? arrivalMins : null,
                            proposedArrivalAt: proposedAt?.toLocal(),
                            nurseNote: item['nurse_note']?.toString(),
                            priceAmount: price,
                            currencyCode: 'ل.س',
                            status: item['status']?.toString() ?? 'PENDING',
                          );

                          return AeroProposalCard(
                            proposal: proposalData,
                            isAccepting: _acceptingProposalId == pId,
                            isDeclining: _decliningProposalId == pId,
                            onAccept: () => _accept(pId),
                            onDecline: () => _decline(pId),
                          );
                        },
                      ),
      ),
    );
  }
}
