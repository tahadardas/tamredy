import 'dart:async';

/// Target route destination when a notification arrives or is tapped.
enum NotificationRouteKind {
  home,
  requestDetail,
  requestTracking,
  requestProposals,
  requestBill,
  nurseOffer,
  nurseAssignment,
  nurseMarketplace,
  chatConversation,
  incomingCall,
  guardian,
  notificationsCenter,
}

class NotificationRouteTarget {
  final NotificationRouteKind kind;
  final String? requestId;
  final String? assignmentId;
  final String? offerId;
  final String? proposalId;
  final String? conversationId;
  final String? callId;
  final String eventType;

  const NotificationRouteTarget({
    required this.kind,
    required this.eventType,
    this.requestId,
    this.assignmentId,
    this.offerId,
    this.proposalId,
    this.conversationId,
    this.callId,
  });
}

class AppNotificationEvent {
  final String eventId;
  final String eventType;
  final String recipientUserId;
  final String recipientRole;
  final String targetApp;
  final String? requestId;
  final String? assignmentId;
  final String? offerId;
  final String? proposalId;
  final String? conversationId;
  final String? callId;
  final int? entityVersion;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String priority;
  final String deepLink;
  final String? title;
  final String? body;
  final Map<String, dynamic> raw;

  const AppNotificationEvent({
    required this.eventId,
    required this.eventType,
    required this.recipientUserId,
    required this.recipientRole,
    required this.targetApp,
    this.requestId,
    this.assignmentId,
    this.offerId,
    this.proposalId,
    this.conversationId,
    this.callId,
    this.entityVersion,
    required this.createdAt,
    this.expiresAt,
    this.priority = 'HIGH',
    this.deepLink = '',
    this.title,
    this.body,
    this.raw = const {},
  });

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s == 'null') ? null : s;
  }

  factory AppNotificationEvent.fromMap(Map<String, dynamic> d, {String? fallbackType}) {
    final type = _nonEmpty(d['eventType']) ?? _nonEmpty(d['type']) ?? fallbackType ?? '';
    final reqId = _nonEmpty(d['requestId']) ?? _nonEmpty(d['request_id']);
    final asgnId = _nonEmpty(d['assignmentId']) ?? _nonEmpty(d['assignment_id']);
    final offerId = _nonEmpty(d['offerId']) ?? _nonEmpty(d['offer_id']);
    final propId = _nonEmpty(d['proposalId']) ?? _nonEmpty(d['proposal_id']);
    final convId = _nonEmpty(d['conversationId']) ?? _nonEmpty(d['conversation_id']);
    final callId = _nonEmpty(d['callId']) ?? _nonEmpty(d['call_id']);
    final fallbackId = '$type:${reqId ?? asgnId ?? offerId ?? propId ?? convId ?? callId ?? DateTime.now().millisecondsSinceEpoch}';

    return AppNotificationEvent(
      eventId: _nonEmpty(d['eventId']) ?? fallbackId,
      eventType: type,
      recipientUserId: _nonEmpty(d['recipientUserId']) ?? '',
      recipientRole: (_nonEmpty(d['recipientRole']) ?? '').toUpperCase(),
      targetApp: (_nonEmpty(d['targetApp']) ?? '').toUpperCase(),
      requestId: reqId,
      assignmentId: asgnId,
      offerId: offerId,
      proposalId: propId,
      conversationId: convId,
      callId: callId,
      entityVersion: int.tryParse('${d['entityVersion'] ?? ''}'),
      createdAt: DateTime.tryParse('${d['createdAt'] ?? ''}') ?? DateTime.now(),
      expiresAt: DateTime.tryParse('${d['expiresAt'] ?? ''}'),
      priority: (_nonEmpty(d['priority']) ?? 'HIGH').toUpperCase(),
      deepLink: _nonEmpty(d['deepLink']) ?? '',
      title: _nonEmpty(d['title']),
      body: _nonEmpty(d['body']),
      raw: Map<String, dynamic>.from(d),
    );
  }
}

/// Central Notification Coordinator:
/// - Enforces strict role & app isolation (drops wrong-role or wrong-app events)
/// - Deduplicates by `eventId` across WebSocket, FCM foreground, FCM tap, and Cold Start
/// - Rejects expired offers/calls before displaying or routing
/// - Resolves deterministic navigation targets (never falls back to just `resync()`)
class NotificationCoordinator {
  final String expectedRole; // PATIENT or NURSE
  final String expectedApp; // PATIENT_APP or NURSE_APP

  final _seenIds = <String>{};
  final _seenOrder = <String>[];
  static const int _maxSeen = 1024;

  final _tapController = StreamController<NotificationRouteTarget>.broadcast();
  final _eventController = StreamController<AppNotificationEvent>.broadcast();

  Stream<NotificationRouteTarget> get onRouteTarget => _tapController.stream;
  Stream<AppNotificationEvent> get onValidatedEvent => _eventController.stream;

  NotificationRouteTarget? pendingColdStartTarget;

  NotificationCoordinator({
    required this.expectedRole,
    required this.expectedApp,
  });

  bool isAuthorizedForThisApp(AppNotificationEvent event) {
    if (event.recipientRole.isNotEmpty && event.recipientRole != expectedRole) {
      return false;
    }
    if (event.targetApp.isNotEmpty && event.targetApp != expectedApp) {
      return false;
    }
    if (expectedRole == 'PATIENT' && const {
      'offer.created',
      'offer.closed',
      'offer.expired',
      'marketplace.proposal.accepted',
      'marketplace.recovery.alert',
      'visit.departure_delayed',
      'safety.checkin_due',
      'safety.checkin_reminder',
      'payment.tip',
    }.contains(event.eventType)) {
      return false;
    }
    if (expectedRole == 'NURSE' && const {
      'request.created',
      'marketplace.proposal.created',
      'marketplace.proposal.withdrawn',
      'request.clinical_review_changed',
      'request.unfulfilled',
      'request.instant.search.expired',
    }.contains(event.eventType)) {
      return false;
    }
    return true;
  }

  /// Processes an incoming event (from WebSocket or Foreground FCM). Returns true if accepted.
  bool acceptEvent(AppNotificationEvent event, {bool dedupe = true}) {
    if (!isAuthorizedForThisApp(event)) return false;
    if ((event.eventType == 'offer.created' || event.eventType == 'call.incoming') &&
        event.isExpired) {
      return false;
    }
    if (dedupe && event.eventId.isNotEmpty) {
      if (_seenIds.contains(event.eventId)) return false;
      _seenIds.add(event.eventId);
      _seenOrder.add(event.eventId);
      if (_seenOrder.length > _maxSeen) {
        _seenIds.remove(_seenOrder.removeAt(0));
      }
    }
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
    return true;
  }

  /// Handles user tapping a notification (Foreground, Background, or Cold Start).
  NotificationRouteTarget? routeFromTap(Map<String, dynamic> rawData, {bool coldStart = false}) {
    final event = AppNotificationEvent.fromMap(rawData);
    if (!isAuthorizedForThisApp(event)) return null;
    if ((event.eventType == 'offer.created' || event.eventType == 'call.incoming') &&
        event.isExpired) {
      return null;
    }
    final target = resolveTarget(event);
    if (coldStart) {
      pendingColdStartTarget = target;
    } else if (!_tapController.isClosed) {
      _tapController.add(target);
    }
    return target;
  }

  NotificationRouteTarget? takePendingColdStartTarget() {
    final t = pendingColdStartTarget;
    pendingColdStartTarget = null;
    return t;
  }

  NotificationRouteTarget resolveTarget(AppNotificationEvent e) {
    if (e.eventType == 'call.incoming' && e.callId != null) {
      return NotificationRouteTarget(
        kind: NotificationRouteKind.incomingCall,
        eventType: e.eventType,
        requestId: e.requestId,
        callId: e.callId,
      );
    }
    if (e.eventType == 'chat.message' && e.conversationId != null) {
      return NotificationRouteTarget(
        kind: NotificationRouteKind.chatConversation,
        eventType: e.eventType,
        requestId: e.requestId,
        conversationId: e.conversationId,
      );
    }
    if (expectedRole == 'NURSE') {
      if (e.eventType == 'offer.created' && e.offerId != null) {
        return NotificationRouteTarget(
          kind: NotificationRouteKind.nurseOffer,
          eventType: e.eventType,
          requestId: e.requestId,
          offerId: e.offerId,
        );
      }
      if (e.eventType == 'marketplace.proposal.accepted' ||
          e.eventType == 'visit.departure_delayed' ||
          e.eventType == 'request.schedule_released') {
        return NotificationRouteTarget(
          kind: NotificationRouteKind.nurseAssignment,
          eventType: e.eventType,
          requestId: e.requestId,
          assignmentId: e.assignmentId,
        );
      }
      if (e.eventType.startsWith('marketplace.')) {
        return NotificationRouteTarget(
          kind: NotificationRouteKind.nurseMarketplace,
          eventType: e.eventType,
          requestId: e.requestId,
        );
      }
      if (e.eventType.startsWith('safety.')) {
        return NotificationRouteTarget(
          kind: NotificationRouteKind.guardian,
          eventType: e.eventType,
          requestId: e.requestId,
          assignmentId: e.assignmentId,
        );
      }
      return NotificationRouteTarget(
        kind: NotificationRouteKind.home,
        eventType: e.eventType,
        requestId: e.requestId,
        assignmentId: e.assignmentId,
      );
    }

    // PATIENT routing
    if (e.eventType == 'marketplace.proposal.created' ||
        e.eventType == 'marketplace.proposal.withdrawn') {
      return NotificationRouteTarget(
        kind: NotificationRouteKind.requestProposals,
        eventType: e.eventType,
        requestId: e.requestId,
        proposalId: e.proposalId,
      );
    }
    if (e.eventType == 'visit.complete' ||
        e.eventType == 'payment.paid' ||
        e.eventType == 'payment.partially_paid' ||
        e.eventType == 'payment.partial') {
      return NotificationRouteTarget(
        kind: NotificationRouteKind.requestBill,
        eventType: e.eventType,
        requestId: e.requestId,
      );
    }
    if (e.eventType == 'request.assigned' ||
        e.eventType == 'visit.depart' ||
        e.eventType == 'visit.arrive' ||
        e.eventType == 'visit.start') {
      return NotificationRouteTarget(
        kind: NotificationRouteKind.requestTracking,
        eventType: e.eventType,
        requestId: e.requestId,
        assignmentId: e.assignmentId,
      );
    }
    if (e.requestId != null) {
      return NotificationRouteTarget(
        kind: NotificationRouteKind.requestDetail,
        eventType: e.eventType,
        requestId: e.requestId,
      );
    }
    return NotificationRouteTarget(
      kind: NotificationRouteKind.notificationsCenter,
      eventType: e.eventType,
    );
  }

  void dispose() {
    _tapController.close();
    _eventController.close();
  }
}
