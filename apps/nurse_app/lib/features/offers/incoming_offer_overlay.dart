import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../core/nurse_session_coordinator.dart';

class IncomingOfferOverlay extends StatefulWidget {
  final NurseSessionCoordinator session;
  final TypedNurseOffer offer;

  const IncomingOfferOverlay({
    super.key,
    required this.session,
    required this.offer,
  });

  @override
  State<IncomingOfferOverlay> createState() => _IncomingOfferOverlayState();
}

class _IncomingOfferOverlayState extends State<IncomingOfferOverlay> {
  Timer? _tick;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  @override
  void didUpdateWidget(covariant IncomingOfferOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offer.offerId != widget.offer.offerId) {
      _updateRemaining();
    }
  }

  void _updateRemaining() {
    final rem = widget.offer.remainingFrom(
      DateTime.now(),
      widget.session.offers.serverOffset,
    );
    if (mounted) {
      setState(() => _remaining = rem);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offerStore = widget.session.offers;
    final offer = widget.offer;
    final secs = _remaining.inSeconds.clamp(0, 60);
    final progress = (secs / 30).clamp(0.0, 1.0);

    return Material(
      color: const Color(0xFF0A1419),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF163B45), Color(0xFF0A1419)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            child: ListenableBuilder(
              listenable: offerStore,
              builder: (context, _) {
                final warn = offerStore.commitmentWarning?['warningMessage']?.toString();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF007F78),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'عرض زيارة فوري • موجة ${offer.waveNo}',
                            style: aeroText(size: 12, weight: FontWeight.w800, color: Colors.white),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'كتم الرنين',
                          onPressed: offerStore.muted ? null : offerStore.muteAlarm,
                          icon: Icon(
                            offerStore.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 112,
                            height: 112,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 7,
                              backgroundColor: Colors.white.withValues(alpha: 0.14),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                secs <= 8 ? const Color(0xFFEF4444) : const Color(0xFF2DD4BF),
                              ),
                            ),
                          ),
                          Text(
                            '$secs ث',
                            style: aeroText(size: 26, weight: FontWeight.w800, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      offer.serviceTitle,
                      textAlign: TextAlign.center,
                      style: aeroText(size: 22, weight: FontWeight.w800, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${offer.area} • يبعد ${offer.distanceKm.toStringAsFixed(1)} كم',
                      textAlign: TextAlign.center,
                      style: aeroText(size: 14.5, color: Colors.white.withValues(alpha: 0.85)),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('صافي حصتك التقديرية',
                                  style: aeroText(size: 13.5, color: Colors.white.withValues(alpha: 0.8))),
                              Text(
                                formatMoney(offer.nurseShare),
                                style: aeroText(size: 20, weight: FontWeight.w800, color: const Color(0xFF2DD4BF)),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white24, height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('المدة المتوقعة',
                                  style: aeroText(size: 13, color: Colors.white.withValues(alpha: 0.75))),
                              Text('${offer.expectedMinutes} دقيقة',
                                  style: aeroText(size: 14, weight: FontWeight.w700, color: Colors.white)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (warn != null && warn.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF78350F),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          warn,
                          textAlign: TextAlign.center,
                          style: aeroText(size: 12.5, color: const Color(0xFFFEF3C7)),
                        ),
                      ),
                    ],
                    if (offerStore.error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        offerStore.error!,
                        textAlign: TextAlign.center,
                        style: aeroText(size: 13, color: const Color(0xFFFCA5A5)),
                      ),
                    ],
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007F78),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: offerStore.acting
                          ? null
                          : () async {
                              final accepted = await offerStore.accept();
                              if (!context.mounted) return;
                              if (!accepted && offerStore.error != null) {
                                TamToast.show(context, offerStore.error!, tone: TamToastTone.warning);
                              }
                            },
                      child: Text(
                        offerStore.acting ? 'جارٍ تثبيت الإسناد...' : 'قبول الطلب والبدء',
                        style: aeroText(size: 16.5, weight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: offerStore.acting ? null : offerStore.decline,
                      child: Text(
                        'تجاهل العرض',
                        style: aeroText(size: 14.5, weight: FontWeight.w700, color: Colors.white70),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
