import 'package:flutter/material.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../core/patient_session_coordinator.dart';
import '../features/booking/booking_wizard_screen.dart';
import '../features/catalog/catalog_store.dart';
import '../features/catalog/service_catalog_screen.dart';
import '../features/communication/visit_chat_screen.dart';
import '../features/finance/invoice_payment_screen.dart';
import '../features/profile/notifications_screen.dart';
import '../features/requests/open_proposals_screen.dart';
import '../features/requests/request_detail_screen.dart';
import '../features/requests/searching_screen.dart';
import '../features/tracking/tracking_screen.dart';

class PatientRouter {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final ValueNotifier<int> currentTab = ValueNotifier(0);

  static NavigatorState? get nav => navigatorKey.currentState;

  static void switchTab(int index) {
    currentTab.value = index;
    nav?.popUntil((r) => r.isFirst);
  }

  static void openServiceCatalog(
    BuildContext context,
    PatientSessionCoordinator session, {
    String? initialCategoryId,
    String? initialQuery,
  }) {
    if (initialCategoryId != null) {
      session.catalog.setCategory(initialCategoryId);
    }
    if (initialQuery != null) {
      session.catalog.setSearchQuery(initialQuery);
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceCatalogScreen(session: session),
      ),
    );
  }

  static void openBookingWizard(
    BuildContext context,
    PatientSessionCoordinator session, {
    PatientService? preselectedService,
    bool startScheduled = false,
  }) {
    if (preselectedService != null) {
      session.bookingDraft.setSingleService(preselectedService);
    }
    if (startScheduled) {
      session.bookingDraft.setBookingMode('SCHEDULED');
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BookingWizardScreen(session: session),
      ),
    );
  }

  static Future<void> openRequestSmart(
    BuildContext context,
    PatientSessionCoordinator session,
    TypedCareRequest req,
  ) async {
    final navState = Navigator.of(context);
    if (req.status == 'OFFERING' && req.bookingMode != 'OPEN') {
      await navState.push(
        MaterialPageRoute<void>(
          builder: (_) => SearchingScreen(session: session, requestId: req.id),
        ),
      );
      return;
    }
    if (req.status == 'OPEN_FOR_PROPOSALS' ||
        (req.bookingMode == 'OPEN' && req.status == 'OFFERING')) {
      await navState.push(
        MaterialPageRoute<void>(
          builder: (_) => OpenProposalsScreen(session: session, requestId: req.id),
        ),
      );
      return;
    }
    if (req.hasAssignedNurse) {
      await navState.push(
        MaterialPageRoute<void>(
          builder: (_) => TrackingScreen(session: session, requestId: req.id),
        ),
      );
      return;
    }
    if (req.isUnpaid) {
      await navState.push(
        MaterialPageRoute<void>(
          builder: (_) => InvoicePaymentScreen(session: session, requestId: req.id),
        ),
      );
      return;
    }
    await navState.push(
      MaterialPageRoute<void>(
        builder: (_) => RequestDetailScreen(session: session, requestId: req.id),
      ),
    );
  }

  static void handleNotificationTarget(
    PatientSessionCoordinator session,
    NotificationRouteTarget target,
  ) {
    final n = nav;
    if (n == null) return;

    switch (target.kind) {
      case NotificationRouteKind.chatConversation:
        if (target.requestId != null && target.requestId!.isNotEmpty) {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => VisitChatScreen(
                session: session,
                requestId: target.requestId!,
                conversationId: target.conversationId,
                peerName: 'الممرض المعتمد',
              ),
            ),
          );
        } else {
          switchTab(2);
        }
        return;

      case NotificationRouteKind.incomingCall:
        session.callManager.showOverlay();
        return;

      case NotificationRouteKind.requestProposals:
        if (target.requestId != null && target.requestId!.isNotEmpty) {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => OpenProposalsScreen(
                session: session,
                requestId: target.requestId!,
              ),
            ),
          );
        } else {
          switchTab(1);
        }
        return;

      case NotificationRouteKind.requestBill:
        if (target.requestId != null && target.requestId!.isNotEmpty) {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => InvoicePaymentScreen(
                session: session,
                requestId: target.requestId!,
              ),
            ),
          );
        } else {
          switchTab(1);
        }
        return;

      case NotificationRouteKind.requestTracking:
      case NotificationRouteKind.requestDetail:
        final reqId = target.requestId;
        if (reqId != null && reqId.isNotEmpty) {
          n.push(
            MaterialPageRoute<void>(
              builder: (_) => RequestDetailScreen(
                session: session,
                requestId: reqId,
              ),
            ),
          );
        } else {
          switchTab(1);
        }
        return;

      case NotificationRouteKind.notificationsCenter:
        n.push(
          MaterialPageRoute<void>(
            builder: (_) => PatientNotificationsScreen(session: session),
          ),
        );
        return;

      case NotificationRouteKind.guardian:
      case NotificationRouteKind.home:
      case NotificationRouteKind.nurseOffer:
      case NotificationRouteKind.nurseAssignment:
      case NotificationRouteKind.nurseMarketplace:
        switchTab(0);
        return;
    }
  }
}
