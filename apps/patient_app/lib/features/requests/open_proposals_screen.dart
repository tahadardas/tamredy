import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';
import '../tracking/tracking_screen.dart';
import 'cancellation_sheet.dart';

class OpenProposalsScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;

  const OpenProposalsScreen({
    super.key,
    required this.session,
    required this.requestId,
  });

  @override
  State<OpenProposalsScreen> createState() => _OpenProposalsScreenState();
}

class _OpenProposalsScreenState extends State<OpenProposalsScreen> {
  bool _loading = true;
  String? _error;
  String? _acceptingId;
  String? _decliningId;
  bool _extending = false;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _fallbackTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      await Future.wait([
        widget.session.requests.loadRequestDetail(widget.requestId),
        widget.session.requests.loadProposals(widget.requestId),
      ]);
      _error = null;
    } catch (e) {
      if (!silent) _error = explainError(e, fallback: 'تعذر تحميل العروض');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(String proposalId) async {
    if (_acceptingId != null) return;
    setState(() => _acceptingId = proposalId);
    try {
      await widget.session.requests.acceptProposal(widget.requestId, proposalId);
      if (!mounted) return;
      TamToast.show(context, 'تم تأكيد اختيار الممرض بنجاح!', tone: TamToastTone.success);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TrackingScreen(
            session: widget.session,
            requestId: widget.requestId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        TamToast.show(
          context,
          explainError(e, fallback: 'تعذر قبول العرض، ربما انتهت صلاحيته'),
          tone: TamToastTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  Future<void> _decline(String proposalId) async {
    if (_decliningId != null) return;
    setState(() => _decliningId = proposalId);
    try {
      await widget.session.requests.declineProposal(widget.requestId, proposalId);
    } catch (e) {
      if (mounted) TamToast.show(context, explainError(e), tone: TamToastTone.error);
    } finally {
      if (mounted) setState(() => _decliningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return ListenableBuilder(
      listenable: widget.session.requests,
      builder: (context, _) {
        final req = widget.session.requests.requestById(widget.requestId);
        final proposals = widget.session.requests
            .proposalsFor(widget.requestId)
            .where((p) => p.status == 'PENDING')
            .toList();

        return TamScaffold(
          title: 'عروض الممرضين',
          subtitle: proposals.isEmpty
              ? 'طلبك منشور الآن لاستقبال عروض الجاهزية'
              : 'اختر العرض الأنسب من حيث وقت الوصول والتقييم',
          showBack: true,
          onRefresh: () => _refresh(),
          children: [
            if (req != null)
              TamCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    KeyValueRow('الخدمة', req.serviceTitle),
                    if (req.addressText != null) KeyValueRow('الموقع', req.addressText!),
                    if (req.openExpiresAt != null)
                      KeyValueRow(
                        'ينتهي النشر',
                        'بعد ${req.openExpiresAt!.difference(DateTime.now()).inMinutes.clamp(0, 999)} دقيقة',
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _extending
                                ? null
                                : () async {
                                    setState(() => _extending = true);
                                    try {
                                      await widget.session.requests.extendOpenWindow(widget.requestId);
                                    } finally {
                                      if (mounted) setState(() => _extending = false);
                                    }
                                  },
                            icon: const Icon(Icons.timer_outlined, size: 18),
                            label: const Text('تمديد (+30 د)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showPatientCancellationSheet(
                              context,
                              widget.session,
                              widget.requestId,
                            ),
                            icon: Icon(Icons.cancel_outlined, size: 18, color: tc.danger),
                            label: Text('إلغاء الطلب', style: TextStyle(color: tc.danger)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (_loading && proposals.isEmpty) ...[
              const TamSkeleton.card(height: 120),
              const SizedBox(height: 10),
              const TamSkeleton.card(height: 120),
            ] else if (_error != null && proposals.isEmpty) ...[
              TamErrorState(
                title: 'تعذر تحميل العروض',
                message: _error!,
                onRetry: () => _refresh(),
              ),
            ] else if (proposals.isEmpty) ...[
              const TamEmptyState(
                icon: Icons.hourglass_top_rounded,
                title: 'بانتظار وصول عروض الممرضين',
                message: 'تم إرسال طلبك إلى الممرضين المؤهلين في منطقتك، وستظهر العروض هنا تلقائياً.',
              ),
            ] else ...[
              for (final p in proposals)
                TamCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: tc.primaryTint,
                            child: Icon(Icons.person_outline_rounded, color: tc.primary),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.nurseName,
                                  style: aeroText(size: 15, weight: FontWeight.w800, color: tc.textPrimary),
                                ),
                                Text(
                                  '⭐ ${p.nurseRating.toStringAsFixed(1)} • ${p.completedOrdersCount} زيارة منجزة',
                                  style: aeroText(size: 12.5, color: tc.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          TamStatusBadge(
                            labelOverride: TimeOfDay.fromDateTime(p.proposedArrivalAt.toLocal()).format(context),
                            compact: true,
                          ),
                        ],
                      ),
                      if (p.note != null && p.note!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          p.note!,
                          style: aeroText(size: 12.5, color: tc.textSecondary, height: 1.45),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: (_acceptingId != null || _decliningId == p.id)
                                  ? null
                                  : () => _decline(p.id),
                              child: Text(_decliningId == p.id ? 'جارٍ الرفض...' : 'تجاهل'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: tc.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: (_acceptingId != null) ? null : () => _accept(p.id),
                              child: Text(
                                _acceptingId == p.id ? 'جارٍ التأكيد...' : 'قبول العرض',
                                style: aeroText(size: 14, weight: FontWeight.w800, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
