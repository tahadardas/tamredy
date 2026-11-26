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

  static String? _lastRouteKey;
  static DateTime _lastRouteAt = DateTime.fromMillisecondsSinceEpoch(0);

  static void handleNotificationTarget(
    NurseSessionCoordinator session,
    NotificationRouteTarget target,
  ) {
    final n = nav;
    if (n == null) return;
    final routeKey = '${target.kind.name}:${target.requestId ?? ''}:${target.assignmentId ?? ''}:${target.conversationId ?? ''}:${target.offerId ?? ''}:${target.callId ?? ''}';
    final now = DateTime.now();
    if (routeKey == _lastRouteKey && now.difference(_lastRouteAt) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastRouteKey = routeKey;
    _lastRouteAt = now;

    switch (target.kind) {
      case NotificationRouteKind.nurseOffer:
        session.offers.fetchOpenOffers();
        return;

      case NotificationRouteKind.nurseAssignment:
        session.visit.restoreActiveAssignment(force: true);
        if (target.assignmentId == null ||
            target.assignmentId == session.visit.assignmentId ||
            target.requestId == session.visit.requestId) {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => VisitWorkspaceScreen(session: session),
            ),
          );
        } else {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => NurseNotificationsScreen(session: session),
            ),
          );
        }
        return;

      case NotificationRouteKind.nurseMarketplace:
        session.marketplace.refreshAll();
        switchTab(1);
        return;

      case NotificationRouteKind.chatConversation:
        // BUG-030: Never substitute current active visit's requestId when notification lacks requestId
        final reqId = target.requestId;
        if (reqId != null && reqId.isNotEmpty) {
          final matchingPatient = (target.requestId == session.visit.requestId)
              ? (session.visit.patientName ?? 'المريض')
              : 'المريض';
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => NurseChatScreen(
                session: session,
                requestId: reqId,
                conversationId: target.conversationId,
                patientName: matchingPatient,
              ),
            ),
          );
        } else {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => NurseNotificationsScreen(session: session),
            ),
          );
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
