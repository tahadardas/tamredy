import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../core/nurse_session_coordinator.dart';
import '../features/communication/nurse_chat_screen.dart';
import '../features/profile/nurse_notifications_screen.dart';
import '../features/safety/guardian_sheet.dart';
import '../features/visit/visit_workspace_screen.dart';

class NurseRouter {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final ValueNotifier<int> currentTab = ValueNotifier(0);

  static NavigatorState? get nav => navigatorKey.currentState;

  static void switchTab(int index) {
    currentTab.value = index;
    nav?.popUntil((r) => r.isFirst);
  }

  static void openVisitWorkspace(
    BuildContext context,
    NurseSessionCoordinator session,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VisitWorkspaceScreen(session: session),
      ),
    );
  }

  static void handleNotificationTarget(
    NurseSessionCoordinator session,
    NotificationRouteTarget target,
  ) {
    final n = nav;
    if (n == null) return;

    switch (target.kind) {
      case NotificationRouteKind.nurseOffer:
        session.offers.fetchOpenOffers();
        switchTab(0);
        return;

      case NotificationRouteKind.nurseAssignment:
        session.visit.restoreActiveAssignment();
        n.push(
          MaterialPageRoute<void>(
            builder: (_) => VisitWorkspaceScreen(session: session),
          ),
        );
        return;

      case NotificationRouteKind.nurseMarketplace:
        session.marketplace.refreshAll();
        switchTab(1);
        return;

      case NotificationRouteKind.chatConversation:
        final reqId = target.requestId ?? session.visit.requestId;
        if (reqId != null && reqId.isNotEmpty) {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => NurseChatScreen(
                session: session,
                requestId: reqId,
                conversationId: target.conversationId,
                patientName: session.visit.patientName ?? 'المريض',
              ),
            ),
          );
        } else {
          switchTab(0);
        }
        return;

      case NotificationRouteKind.incomingCall:
        session.callManager.showOverlay();
        return;

      case NotificationRouteKind.guardian:
        final ctx = n.context;
        openGuardianSheet(ctx, session);
        return;

      case NotificationRouteKind.notificationsCenter:
        n.push(
          MaterialPageRoute<void>(
            builder: (_) => NurseNotificationsScreen(session: session),
          ),
        );
        return;

      default:
        switchTab(0);
        return;
    }
  }
}
