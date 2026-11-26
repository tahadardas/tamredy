import 'package:dio/dio.dart';

/// Explicit network & backend availability states (Phase 9, Section 50).
enum ConnectionHealth {
  online,
  offline,
  reconnecting,
  staleData,
  serverUnavailable,
}

/// Explicit startup initialization lifecycle (BUG-046).
enum SessionInitState {
  idle,
  loading,
  ready,
  partial,
  failed,
}

/// Categorized API failure reasons (Phase 1, Section 6).
enum ApiErrorKind {
  offline,
  timeout,
  serverUnavailable,
  internalError,
  sessionExpired,
  forbidden,
  conflict,
  notFound,
  validation,
  rateLimited,
  featureUnavailable,
  cancelled,
  unknown,
}

class ApiFailure implements Exception {
  final ApiErrorKind kind;
  final int? statusCode;
  final String? code;
  final String messageAr;
  final Object? raw;

  const ApiFailure({
    required this.kind,
    this.statusCode,
    this.code,
    required this.messageAr,
    this.raw,
  });

  @override
  String toString() => 'ApiFailure($kind, code=$code, status=$statusCode): $messageAr';
}

sealed class ApiResult<T> {
  const ApiResult();
  bool get isOk => this is ApiOk<T>;
  bool get isErr => this is ApiErr<T>;
  T? get dataOrNull => this is ApiOk<T> ? (this as ApiOk<T>).data : null;
  ApiFailure? get errorOrNull => this is ApiErr<T> ? (this as ApiErr<T>).failure : null;
}

final class ApiOk<T> extends ApiResult<T> {
  final T data;
  const ApiOk(this.data);
}

final class ApiErr<T> extends ApiResult<T> {
  final ApiFailure failure;
  const ApiErr(this.failure);
}

enum ApiRequestClass {
  health,
  read,
  mutation,
  upload,
}

class RequestTimeoutPolicy {
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;

  const RequestTimeoutPolicy({
    required this.connectTimeout,
    required this.sendTimeout,
    required this.receiveTimeout,
  });

  static RequestTimeoutPolicy forClass(ApiRequestClass kind) {
    switch (kind) {
      case ApiRequestClass.health:
        return const RequestTimeoutPolicy(
          connectTimeout: Duration(seconds: 5),
          sendTimeout: Duration(seconds: 5),
          receiveTimeout: Duration(seconds: 5),
        );
      case ApiRequestClass.read:
        return const RequestTimeoutPolicy(
          connectTimeout: Duration(seconds: 12),
          sendTimeout: Duration(seconds: 10),
          receiveTimeout: Duration(seconds: 15),
        );
      case ApiRequestClass.mutation:
        return const RequestTimeoutPolicy(
          connectTimeout: Duration(seconds: 12),
          sendTimeout: Duration(seconds: 15),
          receiveTimeout: Duration(seconds: 22),
        );
      case ApiRequestClass.upload:
        return const RequestTimeoutPolicy(
          connectTimeout: Duration(seconds: 15),
          sendTimeout: Duration(seconds: 90),
          receiveTimeout: Duration(seconds: 60),
        );
    }
  }

  Options toOptions({Options? base}) {
    final opts = base ?? Options();
    return opts.copyWith(
      sendTimeout: opts.sendTimeout ?? sendTimeout,
      receiveTimeout: opts.receiveTimeout ?? receiveTimeout,
    );
  }
}

class TypedCategory {
  final String id;
  final String code;
  final String titleAr;
  final String? descriptionAr;
  final String? icon;
  final int sortOrder;

  const TypedCategory({
    required this.id,
    required this.code,
    required this.titleAr,
    this.descriptionAr,
    this.icon,
    this.sortOrder = 0,
  });

  factory TypedCategory.fromJson(Map<String, dynamic> j) => TypedCategory(
    id: '${j['id'] ?? ''}',
    code: '${j['code'] ?? ''}',
    titleAr: '${j['title_ar'] ?? j['titleAr'] ?? ''}',
    descriptionAr: j['description_ar']?.toString(),
    icon: j['icon']?.toString(),
    sortOrder: (num.tryParse('${j['sort_order'] ?? 0}') ?? 0).toInt(),
  );
}

class TypedBeneficiary {
  final String id;
  final String displayName;
  final String relationship;
  final String? gender;
  final String? dateOfBirth;
  final String? emergencyContactPhone;

  const TypedBeneficiary({
    required this.id,
    required this.displayName,
    this.relationship = 'SELF',
    this.gender,
    this.dateOfBirth,
    this.emergencyContactPhone,
  });

  factory TypedBeneficiary.fromJson(Map<String, dynamic> j) => TypedBeneficiary(
    id: '${j['id'] ?? ''}',
    displayName: '${j['display_name'] ?? j['displayName'] ?? ''}',
    relationship: '${j['relationship'] ?? 'SELF'}',
    gender: j['gender']?.toString(),
    dateOfBirth: j['date_of_birth']?.toString(),
    emergencyContactPhone: j['emergency_contact_phone']?.toString(),
  );
}

class TypedCareRequestItem {
  final String id;
  final String serviceId;
  final String titleAr;
  final int quantity;
  final int performedQuantity;
  final int unitPrice;
  final int expectedMinutes;
  final int? actualMinutes;
  final String itemStatus;
  final bool requiresPrescription;
  final String? completionNote;
  final String? statusReason;

  const TypedCareRequestItem({
    required this.id,
    required this.serviceId,
    required this.titleAr,
    required this.quantity,
    this.performedQuantity = 0,
    this.unitPrice = 0,
    this.expectedMinutes = 30,
    this.actualMinutes,
    this.itemStatus = 'PENDING',
    this.requiresPrescription = false,
    this.completionNote,
    this.statusReason,
  });

  factory TypedCareRequestItem.fromJson(Map<String, dynamic> j) => TypedCareRequestItem(
    id: '${j['id'] ?? ''}',
    serviceId: '${j['service_id'] ?? j['serviceId'] ?? ''}',
    titleAr: '${j['title_ar'] ?? j['titleAr'] ?? j['service_title'] ?? ''}',
    quantity: (num.tryParse('${j['quantity'] ?? 1}') ?? 1).toInt(),
    performedQuantity: (num.tryParse('${j['performed_quantity'] ?? 0}') ?? 0).toInt(),
    unitPrice: (num.tryParse('${j['unit_price'] ?? j['unitPrice'] ?? 0}') ?? 0).round(),
    expectedMinutes: (num.tryParse('${j['expected_minutes'] ?? j['expectedMinutes'] ?? 30}') ?? 30).toInt(),
    actualMinutes: j['actual_minutes'] != null ? (num.tryParse('${j['actual_minutes']}') ?? 0).toInt() : null,
    itemStatus: '${j['item_status'] ?? j['status'] ?? 'PENDING'}',
    requiresPrescription: j['requires_prescription'] == true,
    completionNote: j['completion_note']?.toString(),
    statusReason: j['status_reason']?.toString(),
  );
}

class TypedCareRequest {
  final String id;
  final String status;
  final int version;
  final int priceAmount;
  final String currencyCode;
  final String bookingMode;
  final String? marketplaceStatus;
  final String? clinicalApprovalStatus;
  final String? paymentStatus;
  final int? amountDue;
  final int tipAmount;
  final String serviceTitle;
  final String beneficiaryName;
  final String? addressText;
  final String? assignedNurseId;
  final String? assignmentId;
  final String? nurseName;
  final int activeProposalsCount;
  final DateTime? createdAt;
  final DateTime? scheduledAt;
  final DateTime? openExpiresAt;
  final DateTime? searchExpiresAt;
  final double? patientLat;
  final double? patientLng;
  final double? nurseLat;
  final double? nurseLng;
  final List<TypedCareRequestItem> items;
  final List<String> allowedActions;
  final bool hasFullDetail;

  const TypedCareRequest({
    required this.id,
    required this.status,
    this.version = 1,
    this.priceAmount = 0,
    this.currencyCode = 'SYP_NEW',
    this.bookingMode = 'INSTANT',
    this.marketplaceStatus,
    this.clinicalApprovalStatus,
    this.paymentStatus,
    this.amountDue,
    this.tipAmount = 0,
    this.serviceTitle = '',
    this.beneficiaryName = '',
    this.addressText,
    this.assignedNurseId,
    this.assignmentId,
    this.nurseName,
    this.activeProposalsCount = 0,
    this.createdAt,
    this.scheduledAt,
    this.openExpiresAt,
    this.searchExpiresAt,
    this.patientLat,
    this.patientLng,
    this.nurseLat,
    this.nurseLng,
    this.items = const [],
    this.allowedActions = const [],
    this.hasFullDetail = false,
  });

  bool get isTerminal => const {'COMPLETED', 'CANCELLED', 'EXPIRED'}.contains(status);

  bool get isActive => const {
    'SCHEDULED',
    'OFFERING',
    'OPEN_FOR_PROPOSALS',
    'AWAITING_RECOVERY_CHOICE',
    'ASSIGNED',
    'EN_ROUTE',
    'ARRIVED',
    'IN_SERVICE',
    'ESCALATED',
  }.contains(status);

  bool get hasAssignedNurse => const {
    'ASSIGNED',
    'EN_ROUTE',
    'ARRIVED',
    'IN_SERVICE',
  }.contains(status);

  bool get isUnpaid =>
      status == 'COMPLETED' && (paymentStatus == 'DUE' || paymentStatus == 'PARTIAL');

  bool get isUnfulfilled => status == 'UNFULFILLED' || status == 'AWAITING_RECOVERY_CHOICE';

  /// Merges [incoming] without letting stale versions or summary rows overwrite richer details.
  TypedCareRequest mergePreferRicher(TypedCareRequest incoming) {
    if (incoming.version < version) return this;
    if (incoming.version == version && isTerminal && !incoming.isTerminal) return this;
    final incomingWinsDetail = incoming.hasFullDetail || !hasFullDetail;
    return TypedCareRequest(
      id: incoming.id.isNotEmpty ? incoming.id : id,
      status: incoming.status.isNotEmpty ? incoming.status : status,
      version: incoming.version,
      priceAmount: incoming.priceAmount != 0 ? incoming.priceAmount : priceAmount,
      currencyCode: incoming.currencyCode.isNotEmpty ? incoming.currencyCode : currencyCode,
      bookingMode: incoming.bookingMode.isNotEmpty ? incoming.bookingMode : bookingMode,
      marketplaceStatus: incoming.marketplaceStatus ?? marketplaceStatus,
      clinicalApprovalStatus: incoming.clinicalApprovalStatus ?? clinicalApprovalStatus,
      paymentStatus: incoming.paymentStatus ?? paymentStatus,
      amountDue: incoming.amountDue ?? amountDue,
      tipAmount: incoming.tipAmount != 0 ? incoming.tipAmount : tipAmount,
      serviceTitle: incoming.serviceTitle.isNotEmpty ? incoming.serviceTitle : serviceTitle,
      beneficiaryName: incoming.beneficiaryName.isNotEmpty ? incoming.beneficiaryName : beneficiaryName,
      addressText: incoming.addressText ?? addressText,
      assignedNurseId: incoming.assignedNurseId ?? assignedNurseId,
      assignmentId: incoming.assignmentId ?? assignmentId,
      nurseName: incoming.nurseName ?? nurseName,
      activeProposalsCount: incoming.activeProposalsCount > 0 ? incoming.activeProposalsCount : activeProposalsCount,
      createdAt: incoming.createdAt ?? createdAt,
      scheduledAt: incoming.scheduledAt ?? scheduledAt,
      openExpiresAt: incoming.openExpiresAt ?? openExpiresAt,
      searchExpiresAt: incoming.searchExpiresAt ?? searchExpiresAt,
      patientLat: incoming.patientLat ?? patientLat,
      patientLng: incoming.patientLng ?? patientLng,
      nurseLat: incoming.nurseLat ?? nurseLat,
      nurseLng: incoming.nurseLng ?? nurseLng,
      items: (incoming.items.isNotEmpty && incomingWinsDetail)
          ? incoming.items
          : (items.isNotEmpty ? items : incoming.items),
      allowedActions: incoming.allowedActions.isNotEmpty ? incoming.allowedActions : allowedActions,
      hasFullDetail: hasFullDetail || incoming.hasFullDetail,
    );
  }

  factory TypedCareRequest.fromJson(Map<String, dynamic> j, {bool fullDetail = false}) {
    final parsedItems = j['items'] is List
        ? [
            for (final item in (j['items'] as List))
              if (item is Map) TypedCareRequestItem.fromJson(Map<String, dynamic>.from(item)),
          ]
        : const <TypedCareRequestItem>[];
    final hasRichFields = fullDetail ||
        j['address_text'] != null ||
        parsedItems.isNotEmpty ||
        j['assignment_id'] != null;
    return TypedCareRequest(
      id: '${j['id'] ?? j['request_id'] ?? ''}',
      status: '${j['status'] ?? j['request_status'] ?? ''}',
      version: (num.tryParse('${j['version'] ?? 1}') ?? 1).toInt(),
      priceAmount: (num.tryParse('${j['price_amount'] ?? 0}') ?? 0).round(),
      currencyCode: '${j['currency_code'] ?? 'SYP_NEW'}',
      bookingMode: '${j['booking_mode'] ?? 'INSTANT'}',
      marketplaceStatus: j['marketplace_status']?.toString(),
      clinicalApprovalStatus: j['clinical_approval_status']?.toString(),
      paymentStatus: j['payment_status']?.toString(),
      amountDue: j['amount_due'] != null ? (num.tryParse('${j['amount_due']}') ?? 0).round() : null,
      tipAmount: (num.tryParse('${j['tip_amount'] ?? 0}') ?? 0).round(),
      serviceTitle: '${j['service_title'] ?? ''}',
      beneficiaryName: '${j['beneficiary_name'] ?? ''}',
      addressText: j['address_text']?.toString(),
      assignedNurseId: (j['assigned_nurse_id'] ?? j['nurse_id'])?.toString(),
      assignmentId: j['assignment_id']?.toString(),
      nurseName: j['nurse_name']?.toString(),
      activeProposalsCount: (num.tryParse('${j['active_proposals_count'] ?? 0}') ?? 0).toInt(),
      createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      scheduledAt: DateTime.tryParse('${j['scheduled_at'] ?? ''}'),
      openExpiresAt: DateTime.tryParse('${j['open_expires_at'] ?? ''}'),
      searchExpiresAt: DateTime.tryParse('${j['search_expires_at'] ?? ''}'),
      patientLat: double.tryParse('${j['patient_lat'] ?? ''}'),
      patientLng: double.tryParse('${j['patient_lng'] ?? ''}'),
      nurseLat: double.tryParse('${j['nurse_lat'] ?? ''}'),
      nurseLng: double.tryParse('${j['nurse_lng'] ?? ''}'),
      items: parsedItems,
      allowedActions: j['allowedActions'] is List
          ? (j['allowedActions'] as List).map((e) => e.toString()).toList()
          : const [],
      hasFullDetail: hasRichFields,
    );
  }
}

/// BUG-001: Strongly-typed nurse assignment recovery snapshot separating
/// `assignmentStatus` (ACTIVE/RESERVED/RELEASED) from `requestStatus` (visit phase).
class TypedAssignmentSnapshot {
  final String assignmentId;
  final String assignmentStatus;
  final String requestId;
  final String requestStatus;
  final int version;
  final bool departureWindowOpen;
  final List<String> allowedActions;
  final String? serviceTitle;
  final String? beneficiaryName;
  final String? patientName;
  final String? addressText;
  final String? bookingMode;
  final double? patientLat;
  final double? patientLng;
  final DateTime? scheduledAt;
  final List<Map<String, dynamic>>? items;

  const TypedAssignmentSnapshot({
    required this.assignmentId,
    required this.assignmentStatus,
    required this.requestId,
    required this.requestStatus,
    this.version = 1,
    this.departureWindowOpen = false,
    this.allowedActions = const [],
    this.serviceTitle,
    this.beneficiaryName,
    this.patientName,
    this.addressText,
    this.bookingMode,
    this.patientLat,
    this.patientLng,
    this.scheduledAt,
    this.items,
  });

  factory TypedAssignmentSnapshot.fromJson(Map<String, dynamic> j) => TypedAssignmentSnapshot(
    assignmentId: '${j['assignment_id'] ?? j['id'] ?? ''}',
    assignmentStatus: '${j['assignment_status'] ?? ''}',
    requestId: '${j['request_id'] ?? j['requestId'] ?? ''}',
    requestStatus: '${j['request_status'] ?? j['status'] ?? ''}',
    version: (num.tryParse('${j['version'] ?? 1}') ?? 1).toInt(),
    departureWindowOpen: j['departure_window_open'] == true,
    allowedActions: j['allowedActions'] is List
        ? (j['allowedActions'] as List).map((e) => e.toString()).toList()
        : const [],
    serviceTitle: j['service_title']?.toString(),
    beneficiaryName: j['beneficiary_name']?.toString(),
    patientName: j['patient_name']?.toString(),
    addressText: j['address_text']?.toString(),
    bookingMode: j['booking_mode']?.toString(),
    patientLat: double.tryParse('${j['patient_lat'] ?? j['latitude'] ?? ''}'),
    patientLng: double.tryParse('${j['patient_lng'] ?? j['longitude'] ?? ''}'),
    scheduledAt: DateTime.tryParse('${j['scheduled_at'] ?? ''}'),
    items: j['items'] is List
        ? (j['items'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : null,
  );
}

/// BUG-003: Typed unpaid invoice record returned by nurse recovery without conflating
/// with an in-progress field visit.
class TypedUnpaidInvoice {
  final String requestId;
  final String assignmentId;
  final String invoiceId;
  final String status;
  final int remaining;
  final String currencyCode;
  final String? serviceTitle;
  final String? beneficiaryName;

  const TypedUnpaidInvoice({
    required this.requestId,
    required this.assignmentId,
    required this.invoiceId,
    required this.status,
    required this.remaining,
    this.currencyCode = 'SYP_NEW',
    this.serviceTitle,
    this.beneficiaryName,
  });

  factory TypedUnpaidInvoice.fromJson(Map<String, dynamic> j) => TypedUnpaidInvoice(
    requestId: '${j['request_id'] ?? j['requestId'] ?? ''}',
    assignmentId: '${j['assignment_id'] ?? j['assignmentId'] ?? ''}',
    invoiceId: '${j['invoice_id'] ?? j['invoiceId'] ?? j['id'] ?? ''}',
    status: '${j['status'] ?? 'ISSUED'}',
    remaining: (num.tryParse('${j['remaining'] ?? 0}') ?? 0).round(),
    currencyCode: '${j['currency_code'] ?? 'SYP_NEW'}',
    serviceTitle: j['service_title']?.toString(),
    beneficiaryName: j['beneficiary_name']?.toString(),
  );
}

class TypedNurseOffer {
  final String offerId;
  final String requestId;
  final String serviceTitle;
  final String area;
  final int distanceMeters;
  final int expectedMinutes;
  final int priceAmount;
  final int nurseShare;
  final int waveNo;
  final DateTime expiresAt;
  final DateTime serverNow;

  const TypedNurseOffer({
    required this.offerId,
    required this.requestId,
    required this.serviceTitle,
    required this.area,
    required this.distanceMeters,
    required this.expectedMinutes,
    required this.priceAmount,
    required this.nurseShare,
    this.waveNo = 1,
    required this.expiresAt,
    required this.serverNow,
  });

  double get distanceKm => distanceMeters / 1000.0;

  Duration remainingFrom(DateTime localNow, Duration serverOffset) {
    final adjustedNow = localNow.add(serverOffset);
    final diff = expiresAt.difference(adjustedNow);
    return diff.isNegative ? Duration.zero : diff;
  }

  factory TypedNurseOffer.fromJson(Map<String, dynamic> j) {
    final serverNow = DateTime.tryParse('${j['server_now'] ?? ''}') ?? DateTime.now();
    final expiresAt = DateTime.tryParse('${j['expires_at'] ?? ''}') ??
        serverNow.add(const Duration(seconds: 30));
    final price = (num.tryParse('${j['price_amount'] ?? 0}') ?? 0).round();
    final bps = (num.tryParse('${j['commission_bps'] ?? 2000}') ?? 2000).toInt();
    final share = j['nurse_share'] != null
        ? (num.tryParse('${j['nurse_share']}') ?? 0).round()
        : (price * (10000 - bps) / 10000).round();
    return TypedNurseOffer(
      offerId: '${j['id'] ?? j['offerId'] ?? ''}',
      requestId: '${j['request_id'] ?? j['requestId'] ?? ''}',
      serviceTitle: '${j['title_ar'] ?? j['service_title'] ?? 'طلب تمريض'}',
      area: '${j['area'] ?? j['approximate_area'] ?? 'ضمن نطاق الخدمة'}',
      distanceMeters: (num.tryParse('${j['distance_m'] ?? 0}') ?? 0).round(),
      expectedMinutes: (num.tryParse('${j['expected_minutes'] ?? 30}') ?? 30).toInt(),
      priceAmount: price,
      nurseShare: share,
      waveNo: (num.tryParse('${j['wave_no'] ?? 1}') ?? 1).toInt(),
      expiresAt: expiresAt,
      serverNow: serverNow,
    );
  }
}

class TypedProposal {
  final String id;
  final String status;
  final String nurseId;
  final String nurseUserId;
  final String nurseName;
  final double nurseRating;
  final int completedOrdersCount;
  final String? licenseTail;
  final DateTime proposedArrivalAt;
  final int estimatedServiceMinutes;
  final String? note;
  final DateTime expiresAt;
  final int proposalVersion;

  const TypedProposal({
    required this.id,
    required this.status,
    required this.nurseId,
    required this.nurseUserId,
    required this.nurseName,
    required this.nurseRating,
    required this.completedOrdersCount,
    this.licenseTail,
    required this.proposedArrivalAt,
    required this.estimatedServiceMinutes,
    this.note,
    required this.expiresAt,
    this.proposalVersion = 1,
  });

  factory TypedProposal.fromJson(Map<String, dynamic> j) => TypedProposal(
    id: '${j['id'] ?? ''}',
    status: '${j['status'] ?? 'PENDING'}',
    nurseId: '${j['nurse_id'] ?? ''}',
    nurseUserId: '${j['nurse_user_id'] ?? ''}',
    nurseName: '${j['nurse_name'] ?? 'ممرض معتمد'}',
    nurseRating: double.tryParse('${j['nurse_rating'] ?? 5.0}') ?? 5.0,
    completedOrdersCount: (num.tryParse('${j['completed_orders_count'] ?? 0}') ?? 0).toInt(),
    licenseTail: j['license_tail']?.toString(),
    proposedArrivalAt: DateTime.tryParse('${j['proposed_arrival_at'] ?? ''}') ?? DateTime.now(),
    estimatedServiceMinutes: (num.tryParse('${j['estimated_service_minutes'] ?? 30}') ?? 30).toInt(),
    note: j['note']?.toString(),
    expiresAt: DateTime.tryParse('${j['expires_at'] ?? ''}') ?? DateTime.now(),
    proposalVersion: (num.tryParse('${j['proposal_version'] ?? 1}') ?? 1).toInt(),
  );
}
