import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/patient_session_coordinator.dart';
import '../tracking/tracking_screen.dart';
import 'cancellation_sheet.dart';
import 'open_proposals_screen.dart';
import 'request_detail_screen.dart';

class SearchingScreen extends StatefulWidget {
  final PatientSessionCoordinator session;
  final String requestId;

  const SearchingScreen({
    super.key,
    required this.session,
    required this.requestId,
  });

  @override
  State<SearchingScreen> createState() => _SearchingScreenState();
}

class _SearchingScreenState extends State<SearchingScreen> {
  Timer? _tickTimer;
  Timer? _pollTimer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    widget.session.requests.loadRequestDetail(widget.requestId);
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 12), (_) => _syncAndCheckRoute());
    widget.session.requests.addListener(_onRequestsChanged);
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _pollTimer?.cancel();
    widget.session.requests.removeListener(_onRequestsChanged);
    super.dispose();
  }

  void _onRequestsChanged() {
    if (!mounted) return;
    final req = widget.session.requests.requestById(widget.requestId);
    if (req == null) return;
    if (req.hasAssignedNurse) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TrackingScreen(session: widget.session, requestId: req.id),
        ),
      );
    } else if (req.status == 'OPEN_FOR_PROPOSALS') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OpenProposalsScreen(session: widget.session, requestId: req.id),
        ),
      );
    } else if (req.status == 'UNFULFILLED' || req.status == 'AWAITING_RECOVERY_CHOICE') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RequestDetailScreen(session: widget.session, requestId: req.id),
        ),
      );
    }
  }

  Future<void> _syncAndCheckRoute() async {
    await widget.session.requests.loadRequestDetail(widget.requestId);
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return ListenableBuilder(
      listenable: widget.session.requests,
      builder: (context, _) {
        final req = widget.session.requests.requestById(widget.requestId);
        return TamScaffold(
          title: 'جارٍ البحث عن ممرض',
          subtitle: 'نبحث عن أقرب كادر مؤهل ومتاح لطلبك',
          showBack: true,
          onRefresh: _syncAndCheckRoute,
          children: [
            TamMap(
              height: 190,
              patient: (req?.patientLat != null && req?.patientLng != null)
                  ? LatLng(req!.patientLat!, req.patientLng!)
                  : kDamascus,
            ),
            const SizedBox(height: 12),
            TamCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: tc.primaryTint,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.radar_rounded, size: 42, color: tc.primary),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'يتم إرسال الطلب للممرضين القريبين',
                    textAlign: TextAlign.center,
                    style: aeroText(size: 17.5, weight: FontWeight.w800, color: tc.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'مدة البحث الحالية: ${formatCountdown(Duration(seconds: _elapsedSeconds))}',
                    style: aeroText(size: 13.5, weight: FontWeight.w700, color: tc.primary),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'ستصلك إشارة فورية بمجرد قبول أحد الممرضين، ويمكنك العودة للشاشة الرئيسية وسنُعلمك تلقائياً.',
                    textAlign: TextAlign.center,
                    style: aeroText(size: 12.5, color: tc.textSecondary, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  if (req != null) ...[
                    KeyValueRow('الخدمة', req.serviceTitle),
                    if (req.addressText != null) KeyValueRow('الموقع', req.addressText!),
                  ],
                ],
              ),
            ),
            PrimaryButton(
              'نشر الطلب في السوق المفتوح للعروض',
              onPressed: () async {
                final nav = Navigator.of(context);
                try {
                  await widget.session.requests.switchToOpenMarketplace(widget.requestId);
                  if (!mounted) return;
                  nav.pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => OpenProposalsScreen(
                        session: widget.session,
                        requestId: widget.requestId,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  TamToast.show(context, explainError(e), tone: TamToastTone.error);
                }
              },
            ),
            SoftButton(
              'إلغاء الطلب',
              onPressed: () => showPatientCancellationSheet(
                context,
                widget.session,
                widget.requestId,
              ),
            ),
          ],
        );
      },
    );
  }
}
