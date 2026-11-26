import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../core/nurse_session_coordinator.dart';
import '../guardian.dart';
import '../features/calendar/nurse_calendar_screen.dart';
import '../features/finance/financial_center_screen.dart';
import '../features/home/nurse_home_screen.dart';
import '../features/marketplace/marketplace_screen.dart';
import '../features/offers/incoming_offer_overlay.dart';
import '../features/profile/nurse_profile_screen.dart';
import '../features/safety/guardian_sheet.dart';
import 'nurse_router.dart';

class NurseShell extends StatelessWidget {
  final NurseSessionCoordinator session;

  const NurseShell({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return Stack(
      children: [
        ValueListenableBuilder<int>(
          valueListenable: NurseRouter.currentTab,
          builder: (context, tabIndex, _) {
            final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
            return Scaffold(
              backgroundColor: tc.background,
              body: Column(
                children: [
                  TamConnectionBanner(
                    health: session.api.connectionHealth,
                    onRetry: session.resyncAll,
                  ),
                  if (guardianEnabled) _GuardianSosTopBar(session: session),
                  Expanded(
                    child: IndexedStack(
                      index: tabIndex,
                      children: [
                        NurseHomeScreen(session: session),
                        MarketplaceScreen(session: session),
                        NurseCalendarScreen(session: session),
                        FinancialCenterScreen(session: session),
                        NurseProfileScreen(session: session),
                      ],
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: keyboardOpen
                  ? null
                  : _NurseBottomBar(
                      currentIndex: tabIndex,
                      onTap: (i) => NurseRouter.currentTab.value = i,
                    ),
            );
          },
        ),
        // Global full-screen Incoming Offer Overlay: appears over ALL tabs & pushed routes.
        ListenableBuilder(
          listenable: session.offers,
          builder: (context, _) {
            final offer = session.offers.activeOffer;
            if (offer == null) return const SizedBox.shrink();
            return Positioned.fill(
              child: IncomingOfferOverlay(
                session: session,
                offer: offer,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _GuardianSosTopBar extends StatelessWidget {
  final NurseSessionCoordinator session;
  const _GuardianSosTopBar({required this.session});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session.guardian,
      builder: (context, _) {
        final g = session.guardian;
        final active = g.sessionId != null || g.sosUnconfirmed;
        if (!active && !session.visit.hasActiveWork) {
          return const SizedBox.shrink();
        }
        return Material(
          color: g.sosUnconfirmed ? const Color(0xFFDC2626) : const Color(0xFF163B45),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () => openGuardianSheet(context, session),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  children: [
                    const Icon(Icons.shield_rounded, color: Colors.white, size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        g.sosUnconfirmed
                            ? 'بلاغ استغاثة بانتظار التأكيد — اضغط للمتابعة'
                            : 'ميزة الأمان Guardian نشطة أثناء المهمة',
                        style: aeroText(size: 12, weight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        'SOS',
                        style: aeroText(size: 11, weight: FontWeight.w800, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NurseBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NurseBottomBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    const items = [
      (Icons.dashboard_rounded, Icons.dashboard_outlined, 'الرئيسية'),
      (Icons.storefront_rounded, Icons.storefront_outlined, 'السوق'),
      (Icons.calendar_month_rounded, Icons.calendar_month_outlined, 'الجدول'),
      (Icons.account_balance_wallet_rounded, Icons.account_balance_wallet_outlined, 'المالية'),
      (Icons.person_rounded, Icons.person_outline_rounded, 'ملفي'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: tc.navBackground,
        border: Border(top: BorderSide(color: tc.border)),
        boxShadow: tc.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    selected: i == currentIndex,
                    button: true,
                    label: items[i].$3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onTap(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == currentIndex
                              ? tc.primaryTint.withValues(alpha: tc.isDark ? 0.35 : 0.75)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              i == currentIndex ? items[i].$1 : items[i].$2,
                              size: 21,
                              color: i == currentIndex ? tc.primary : tc.textSecondary,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              items[i].$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: aeroText(
                                size: 10.5,
                                weight: i == currentIndex ? FontWeight.w800 : FontWeight.w600,
                                color: i == currentIndex ? tc.primary : tc.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
