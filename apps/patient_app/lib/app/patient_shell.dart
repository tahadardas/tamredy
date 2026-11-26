import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../core/patient_session_coordinator.dart';
import '../features/communication/messages_tab_screen.dart';
import '../features/home/patient_home_screen.dart';
import '../features/profile/patient_profile_screen.dart';
import '../features/requests/requests_center_screen.dart';
import 'patient_router.dart';

class PatientShell extends StatelessWidget {
  final PatientSessionCoordinator session;

  const PatientShell({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;

    return ValueListenableBuilder<int>(
      valueListenable: PatientRouter.currentTab,
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
              Expanded(
                child: IndexedStack(
                  index: tabIndex,
                  children: [
                    PatientHomeScreen(session: session),
                    RequestsCenterScreen(session: session),
                    MessagesTabScreen(session: session),
                    PatientProfileScreen(session: session),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: keyboardOpen
              ? null
              : ListenableBuilder(
                  listenable: Listenable.merge([session.requests, session.conversations]),
                  builder: (context, _) {
                    final activeCount = session.requests.activeRequests.length +
                        session.requests.unpaidBills.length;
                    final unreadChats = session.conversations.totalUnread;
                    return _PatientBottomBar(
                      currentIndex: tabIndex,
                      requestsBadge: activeCount,
                      messagesBadge: unreadChats,
                      onTap: (i) => PatientRouter.currentTab.value = i,
                    );
                  },
                ),
        );
      },
    );
  }
}

class _PatientBottomBar extends StatelessWidget {
  final int currentIndex;
  final int requestsBadge;
  final int messagesBadge;
  final ValueChanged<int> onTap;

  const _PatientBottomBar({
    required this.currentIndex,
    required this.requestsBadge,
    required this.messagesBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final items = [
      (Icons.home_rounded, Icons.home_outlined, 'الرئيسية', 0),
      (Icons.assignment_rounded, Icons.assignment_outlined, 'طلباتي', requestsBadge),
      (Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, 'الرسائل', messagesBadge),
      (Icons.person_rounded, Icons.person_outline_rounded, 'حسابي', 0),
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTabButton(
                    selected: i == currentIndex,
                    activeIcon: items[i].$1,
                    idleIcon: items[i].$2,
                    label: items[i].$3,
                    badgeCount: items[i].$4,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTabButton extends StatelessWidget {
  final bool selected;
  final IconData activeIcon;
  final IconData idleIcon;
  final String label;
  final int badgeCount;
  final VoidCallback onTap;

  const _NavTabButton({
    required this.selected,
    required this.activeIcon,
    required this.idleIcon,
    required this.label,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tc = context.tamColors;
    final color = selected ? tc.primary : tc.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? tc.primaryTint.withValues(alpha: tc.isDark ? 0.35 : 0.75) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(selected ? activeIcon : idleIcon, color: color, size: 22),
                  if (badgeCount > 0)
                    PositionedDirectional(
                      top: -4,
                      end: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: tc.danger,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: aeroText(size: 9.5, weight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: aeroText(
                  size: 11,
                  weight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
