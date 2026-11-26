import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../catalog/catalog_store.dart';

enum EstimateStatus {
  verified,
  unavailable,
  stale,
}

class RegionArea {
  final String governorate;
  final String name;
  final double? lat;
  final double? lng;
  const RegionArea({required this.governorate, required this.name, this.lat, this.lng});
}

class SavedPlaceModel {
  final String id;
  final String label;
  final String placeType;
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final double accuracy;
  final String? building;
  final String? floor;
  final String? landmark;
  final String? notes;
  final bool isDefault;

  const SavedPlaceModel({
    required this.id,
    required this.label,
    required this.placeType,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.accuracy = 0,
    this.building,
    this.floor,
    this.landmark,
    this.notes,
    this.isDefault = false,
  });

  LatLng get point => LatLng(latitude, longitude);

  String get detailsSummary => [
        if (building != null && building!.trim().isNotEmpty) 'البناء ${building!.trim()}',
        if (floor != null && floor!.trim().isNotEmpty) 'الطابق ${floor!.trim()}',
        if (landmark != null && landmark!.trim().isNotEmpty) landmark!.trim(),
        if (notes != null && notes!.trim().isNotEmpty) notes!.trim(),
      ].join(' • ');

  factory SavedPlaceModel.fromJson(Map<String, dynamic> j) => SavedPlaceModel(
        id: '${j['id'] ?? ''}',
        label: '${j['label'] ?? 'عنوان محفوظ'}',
        placeType: '${j['place_type'] ?? 'CUSTOM'}',
        formattedAddress: '${j['formatted_address'] ?? ''}',
        latitude: (num.tryParse('${j['latitude'] ?? 0}') ?? 0).toDouble(),
        longitude: (num.tryParse('${j['longitude'] ?? 0}') ?? 0).toDouble(),
        accuracy: (num.tryParse('${j['accuracy'] ?? 0}') ?? 0).toDouble(),
        building: j['building']?.toString(),
        floor: j['floor']?.toString(),
        landmark: j['landmark']?.toString(),
        notes: j['notes']?.toString(),
        isDefault: j['is_default'] == true,
      );
}

class StagedEvidence {
  final String evidenceType; // PRESCRIPTION | CLINICAL_REPORT
  final String filename;
  final Uint8List bytes;
  const StagedEvidence({
    required this.evidenceType,
    required this.filename,
    required this.bytes,
  });
}

class BookingDraftStore extends ChangeNotifier {
  static const _draftStorageKey = 'patient_booking_draft_v3';

  final TamreedyApi api;
  final CatalogStore catalog;

  BookingDraftStore({required this.api, required this.catalog});

  // Step 1: Services & pricing
  final Map<String, int> serviceQuantities = {};
  String promoCode = '';
  String? promoFeedback;
  CatalogEstimateResult? estimate;
  EstimateStatus estimateStatus = EstimateStatus.stale;
  int _estimateGeneration = 0;
  Timer? _estimateDebounce;
  bool estimating = false;

  int get unverifiedLocalSubtotal {
    var total = 0;
    for (final entry in serviceQuantities.entries) {
      final s = catalog.byId(entry.key);
      if (s != null) total += s.priceAmount * entry.value;
    }
    return total;
  }

  int get unverifiedLocalMinutes {
    var mins = 0;
    for (final entry in serviceQuantities.entries) {
      final s = catalog.byId(entry.key);
      if (s != null) mins += s.expectedMinutes * entry.value;
    }
    return mins;
  }

  // Step 2: Beneficiary & location
  List<TypedBeneficiary> beneficiaries = [];
  String? selectedBeneficiaryId;
  bool loadingBeneficiaries = false;

  List<SavedPlaceModel> savedPlaces = [];
  List<RegionArea> regions = [];
  LatLng? locationPoint;
  String addressLabel = '';
  String addressDetails = '';
  double accuracyMeters = 0;
  String locationSource = 'MANUAL_PIN';
  bool locatingGps = false;
  String? locationError;

  // Step 3: Booking mode, schedule & clinical attachment
  String bookingMode = 'INSTANT'; // INSTANT | OPEN | SCHEDULED
  int openDurationMinutes = 60;
  DateTime? scheduledAt;
  Map<String, dynamic>? schedulingPolicy;
  StagedEvidence? stagedEvidence;
  bool prescriptionConfirmed = false;
  ServerCapabilities capabilities = const ServerCapabilities(
    scheduledVisitsEnabled: kDemoMode,
  );

  // Step 4: Submission state & BUG-026 clinical evidence retry state
  String? _idempotencyKey;
  bool submitting = false;
  String? submitError;
  String? pendingEvidenceRequestId;
  String? pendingEvidenceError;
  bool uploadingPendingEvidence = false;

  List<PatientService> get selectedServices {
    final result = <PatientService>[];
    for (final sid in serviceQuantities.keys) {
      final svc = catalog.byId(sid);
      if (svc != null) result.add(svc);
    }
    return result;
  }

  bool get requiresPrescription =>
      selectedServices.any((s) => s.requiresPrescription) ||
      (estimate?.requiresPrescription ?? false);

  bool get requiresClinicalReview =>
      selectedServices.any((s) => s.requiresClinicalReview) ||
      (estimate?.requiresClinicalReview ?? false);

  TypedBeneficiary? get selectedBeneficiary {
    for (final b in beneficiaries) {
      if (b.id == selectedBeneficiaryId) return b;
    }
    return beneficiaries.isEmpty ? null : beneficiaries.first;
  }

  String get fullAddress =>
      [addressLabel.trim(), addressDetails.trim()].where((e) => e.isNotEmpty).join(' • ');

  Future<void> restoreDraft() async {
    try {
      final raw = await api.readLocal(_draftStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final items = decoded['quantities'];
      if (items is Map) {
        serviceQuantities
          ..clear()
          ..addEntries(
            items.entries
                .map((e) => MapEntry('${e.key}', (num.tryParse('${e.value}') ?? 1).toInt().clamp(1, 10)))
                .take(10),
          );
      }
      promoCode = '${decoded['promoCode'] ?? ''}';
      selectedBeneficiaryId = decoded['beneficiaryId']?.toString();
      final lat = double.tryParse('${decoded['lat'] ?? ''}');
      final lng = double.tryParse('${decoded['lng'] ?? ''}');
      if (lat != null && lng != null) {
        locationPoint = LatLng(lat, lng);
      }
      addressLabel = '${decoded['addressLabel'] ?? ''}';
      addressDetails = '${decoded['addressDetails'] ?? ''}';
      bookingMode = '${decoded['bookingMode'] ?? 'INSTANT'}';
      openDurationMinutes = (num.tryParse('${decoded['openDurationMinutes'] ?? 60}') ?? 60).toInt();
      scheduledAt = DateTime.tryParse('${decoded['scheduledAt'] ?? ''}')?.toLocal();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistDraft() async {
    try {
      await api.writeLocal(
        _draftStorageKey,
        jsonEncode({
          'quantities': serviceQuantities,
          'promoCode': promoCode,
          'beneficiaryId': selectedBeneficiaryId,
          'lat': locationPoint?.latitude,
          'lng': locationPoint?.longitude,
          'addressLabel': addressLabel,
          'addressDetails': addressDetails,
          'bookingMode': bookingMode,
          'openDurationMinutes': openDurationMinutes,
          'scheduledAt': scheduledAt?.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  void _invalidateSubmissionKey() {
    _idempotencyKey = null;
    submitError = null;
  }

  void setSingleService(PatientService svc) {
    serviceQuantities
      ..clear()
      ..[svc.id] = 1;
    promoFeedback = null;
    estimateStatus = EstimateStatus.stale;
    _invalidateSubmissionKey();
    _persistDraft();
    notifyListeners();
    refreshEstimate(immediate: true);
  }

  void setServiceQuantity(PatientService svc, int qty) {
    if (qty <= 0) {
      serviceQuantities.remove(svc.id);
    } else {
      if (!serviceQuantities.containsKey(svc.id) && serviceQuantities.length >= 10) {
        return;
      }
      serviceQuantities[svc.id] = qty.clamp(1, 10);
    }
    promoFeedback = null;
    estimateStatus = EstimateStatus.stale;
    _invalidateSubmissionKey();
    _persistDraft();
    notifyListeners();
    refreshEstimate();
  }

  Future<void> refreshEstimate({bool immediate = false}) async {
    _estimateDebounce?.cancel();
    if (serviceQuantities.isEmpty) {
      _estimateGeneration++;
      estimate = null;
      estimateStatus = EstimateStatus.stale;
      estimating = false;
      notifyListeners();
      return;
    }
    if (!immediate) {
      final completer = Completer<void>();
      _estimateDebounce = Timer(const Duration(milliseconds: 280), () async {
        await refreshEstimate(immediate: true);
        if (!completer.isCompleted) completer.complete();
      });
      return completer.future;
    }

    final gen = ++_estimateGeneration;
    estimating = true;
    estimateStatus = EstimateStatus.stale;
    notifyListeners();
    try {
      final result = await catalog.estimate(
        quantities: Map<String, int>.from(serviceQuantities),
        promoCode: promoCode,
      );
      if (gen != _estimateGeneration) return;
      estimate = result;
      estimateStatus = result != null ? EstimateStatus.verified : EstimateStatus.unavailable;
    } catch (e) {
      if (gen != _estimateGeneration) return;
      // BUG-009: never forge a verified CatalogEstimateResult from local sums; preserve error state.
      estimate = null;
      estimateStatus = EstimateStatus.unavailable;
      if (promoCode.trim().isNotEmpty) {
        promoFeedback = explainError(e, fallback: 'تعذر التحقق من الكود أو السعر الرسمي حالياً');
      }
    } finally {
      if (gen == _estimateGeneration) {
        estimating = false;
        notifyListeners();
      }
    }
  }

  Future<void> applyPromo(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    promoCode = code;
    promoFeedback = null;
    estimateStatus = EstimateStatus.stale;
    _invalidateSubmissionKey();
    if (code.isEmpty) {
      await refreshEstimate(immediate: true);
      await _persistDraft();
      return;
    }
    final gen = ++_estimateGeneration;
    estimating = true;
    notifyListeners();
    try {
      final result = await catalog.estimate(
        quantities: Map<String, int>.from(serviceQuantities),
        promoCode: code,
      );
      if (gen != _estimateGeneration) return;
      estimate = result;
      estimateStatus = result != null ? EstimateStatus.verified : EstimateStatus.unavailable;
      if ((estimate?.promoDiscount ?? 0) > 0 || estimate?.promoAppliedCode != null) {
        promoFeedback = 'تم تطبيق الكود ($code)';
      } else {
        promoFeedback = 'تم تسجيل الكود وسيُتحقق منه عند التثبيت';
      }
    } catch (e) {
      if (gen != _estimateGeneration) return;
      estimateStatus = EstimateStatus.unavailable;
      promoFeedback = explainError(e, fallback: 'رمز الخصم غير صالح أو تعذر التحقق من السعر');
    } finally {
      if (gen == _estimateGeneration) {
        estimating = false;
        notifyListeners();
      }
    }
    await _persistDraft();
    notifyListeners();
  }

  Future<void> loadPrerequisites() async {
    await Future.wait([
      catalog.load(),
      loadBeneficiaries(),
      loadSavedPlaces(),
      loadRegions(),
      loadSchedulingPolicy(),
    ]);
    if (serviceQuantities.isNotEmpty && estimate == null) {
      await refreshEstimate(immediate: true);
    }
  }

  Future<void> loadBeneficiaries() async {
    if (kDemoMode) {
      if (beneficiaries.isEmpty) {
        beneficiaries = const [TypedBeneficiary(id: 'demo-ben-1', displayName: 'المستخدم الحالي', relationship: 'SELF')];
      }
      selectedBeneficiaryId ??= beneficiaries.first.id;
      notifyListeners();
      return;
    }
    loadingBeneficiaries = true;
    notifyListeners();
    try {
      final rows = await api.getList('/v1/beneficiaries/mine');
      beneficiaries = [
        for (final row in rows)
          if (row is Map) TypedBeneficiary.fromJson(Map<String, dynamic>.from(row)),
      ];
      if (beneficiaries.isNotEmpty &&
          (selectedBeneficiaryId == null ||
              !beneficiaries.any((b) => b.id == selectedBeneficiaryId))) {
        selectedBeneficiaryId = beneficiaries.first.id;
      }
    } catch (_) {}
    loadingBeneficiaries = false;
    notifyListeners();
  }

  Future<TypedBeneficiary?> createBeneficiary({
    required String displayName,
    String relationship = 'OTHER',
    String? gender,
    String? emergencyContactPhone,
  }) async {
    if (kDemoMode) {
      final ben = TypedBeneficiary(
        id: 'demo-ben-${DateTime.now().millisecondsSinceEpoch}',
        displayName: displayName,
        relationship: relationship,
        gender: gender,
        emergencyContactPhone: emergencyContactPhone,
      );
      beneficiaries = [ben, ...beneficiaries];
      selectedBeneficiaryId = ben.id;
      notifyListeners();
      return ben;
    }
    final res = await api.post('/v1/beneficiaries', {
      'displayName': displayName.trim(),
      'relationship': relationship,
      'gender': ?gender,
      if (emergencyContactPhone != null && emergencyContactPhone.trim().isNotEmpty)
        'emergencyContactPhone': emergencyContactPhone.trim(),
      'consentConfirmed': true,
    });
    final created = TypedBeneficiary.fromJson(res);
    beneficiaries = [created, ...beneficiaries];
    selectedBeneficiaryId = created.id;
    await _persistDraft();
    notifyListeners();
    return created;
  }

  Future<void> removeBeneficiary(String id) async {
    await api.delete('/v1/beneficiaries/$id');
    beneficiaries.removeWhere((b) => b.id == id);
    if (selectedBeneficiaryId == id) {
      selectedBeneficiaryId = beneficiaries.isEmpty ? null : beneficiaries.first.id;
    }
    notifyListeners();
  }

  void selectBeneficiary(String id) {
    selectedBeneficiaryId = id;
    _invalidateSubmissionKey();
    _persistDraft();
    notifyListeners();
  }

  Future<void> loadSavedPlaces() async {
    if (kDemoMode) return;
    try {
      final rows = await api.getList('/v1/patient/saved-places');
      savedPlaces = [
        for (final row in rows)
          if (row is Map) SavedPlaceModel.fromJson(Map<String, dynamic>.from(row)),
      ];
      // Pre-fill default place if no location set yet
      if (locationPoint == null && savedPlaces.isNotEmpty) {
        final def = savedPlaces.where((p) => p.isDefault).firstOrNull ?? savedPlaces.first;
        applySavedPlace(def, persistUse: false);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> applySavedPlace(SavedPlaceModel place, {bool persistUse = true}) async {
    SavedPlaceModel chosen = place;
    if (persistUse && !kDemoMode) {
      try {
        final res = await api.post('/v1/patient/saved-places/${place.id}/use', {});
        chosen = SavedPlaceModel.fromJson(res);
      } catch (_) {}
    }
    locationPoint = chosen.point;
    addressLabel = chosen.formattedAddress.isNotEmpty ? chosen.formattedAddress : chosen.label;
    addressDetails = chosen.detailsSummary;
    accuracyMeters = chosen.accuracy;
    locationSource = 'MANUAL_PIN';
    locationError = null;
    _invalidateSubmissionKey();
    await _persistDraft();
    notifyListeners();
  }

  Future<void> loadRegions() async {
    if (kDemoMode) {
      regions = const [
        RegionArea(governorate: 'دمشق', name: 'المزة', lat: 33.5000, lng: 36.2500),
        RegionArea(governorate: 'دمشق', name: 'المالكي', lat: 33.5200, lng: 36.2800),
        RegionArea(governorate: 'دمشق', name: 'كفرسوسة', lat: 33.4930, lng: 36.2760),
        RegionArea(governorate: 'ريف دمشق', name: 'جرمانا', lat: 33.4750, lng: 36.3500),
      ];
      notifyListeners();
      return;
    }
    try {
      final d = await api.getMap('/v1/catalog/regions');
      final list = <RegionArea>[];
      for (final g in (d['governorates'] as List? ?? const [])) {
        if (g is! Map) continue;
        final govName = '${g['name'] ?? ''}';
        for (final a in (g['areas'] as List? ?? const [])) {
          if (a is! Map) continue;
          list.add(RegionArea(
            governorate: govName,
            name: '${a['name'] ?? ''}',
            lat: double.tryParse('${a['lat'] ?? ''}'),
            lng: double.tryParse('${a['lng'] ?? ''}'),
          ));
        }
      }
      regions = list;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadSchedulingPolicy() async {
    if (kDemoMode) return;
    try {
      schedulingPolicy = await api.getMap('/v1/requests/scheduling');
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> captureGpsLocation() async {
    locationError = null;
    locatingGps = true;
    notifyListeners();
    try {
      if (kDemoMode) {
        locationPoint = kDamascus;
        addressLabel = 'موقعي الحالي (تجريبي)';
        accuracyMeters = 10;
        locationSource = 'GPS_CONFIRMED';
        return true;
      }
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        locationError = 'خدمة تحديد الموقع (GPS) مغلقة على جهازك. فعّلها ثم أعد المحاولة.';
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        locationError = 'تم رفض إذن الموقع نهائياً. اسمح بالوصول من إعدادات التطبيق.';
        return false;
      }
      if (perm == LocationPermission.denied) {
        locationError = 'يلزم السماح بإذن الموقع لتحديد عنوان الزيارة بدقة.';
        return false;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      locationPoint = LatLng(pos.latitude, pos.longitude);
      accuracyMeters = pos.accuracy;
      locationSource = 'GPS_CONFIRMED';
      if (addressLabel.isEmpty) addressLabel = 'موقعي الحالي';
      _invalidateSubmissionKey();
      await _persistDraft();
      return true;
    } catch (_) {
      locationError = 'تعذر التقاط إشارة GPS حالياً. حدّد موقعك على الخريطة أو اختر المنطقة.';
      return false;
    } finally {
      locatingGps = false;
      notifyListeners();
    }
  }

  void setMapPoint(LatLng point, String resolvedLabel, {double? accuracy}) {
    locationPoint = point;
    if (resolvedLabel.trim().isNotEmpty) {
      addressLabel = resolvedLabel.trim();
    } else if (addressLabel.isEmpty) {
      addressLabel = 'الموقع المحدد على الخريطة';
    }
    if (accuracy != null) accuracyMeters = accuracy;
    locationSource = 'MANUAL_PIN';
    locationError = null;
    _invalidateSubmissionKey();
    _persistDraft();
    notifyListeners();
  }

  void setAddressDetails(String details) {
    addressDetails = details;
    _persistDraft();
    notifyListeners();
  }

  void updateCapabilities(ServerCapabilities next) {
    capabilities = next;
    if (!capabilities.scheduledVisitsEnabled && bookingMode == 'SCHEDULED') {
      bookingMode = 'INSTANT';
      scheduledAt = null;
      _invalidateSubmissionKey();
      _persistDraft();
    }
    notifyListeners();
  }

  void setBookingMode(String mode) {
    if (mode == 'SCHEDULED' && !capabilities.scheduledVisitsEnabled) {
      return;
    }
    bookingMode = mode;
    if (mode != 'SCHEDULED') scheduledAt = null;
    _invalidateSubmissionKey();
    _persistDraft();
    notifyListeners();
  }

  void setOpenDurationMinutes(int mins) {
    openDurationMinutes = mins;
    _persistDraft();
    notifyListeners();
  }

  void setScheduledAt(DateTime? dt) {
    scheduledAt = dt;
    if (dt != null) bookingMode = 'SCHEDULED';
    _invalidateSubmissionKey();
    _persistDraft();
    notifyListeners();
  }

  void setStagedEvidence(StagedEvidence? ev) {
    stagedEvidence = ev;
    if (ev != null) prescriptionConfirmed = true;
    notifyListeners();
  }

  void setPrescriptionConfirmed(bool val) {
    prescriptionConfirmed = val;
    notifyListeners();
  }

  /// Submits the request with single-flight protection & Idempotency-Key.
  Future<TypedCareRequest?> submit() async {
    if (submitting || serviceQuantities.isEmpty) return null;
    final pt = locationPoint;
    if (pt == null) {
      submitError = 'يرجى تحديد موقع الزيارة على الخريطة قبل الإرسال.';
      notifyListeners();
      return null;
    }
    if (bookingMode == 'SCHEDULED' && scheduledAt == null) {
      submitError = 'يرجى اختيار تاريخ ووقت الزيارة المجدولة.';
      notifyListeners();
      return null;
    }

    submitting = true;
    submitError = null;
    notifyListeners();

    try {
      if (kDemoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final firstSvc = selectedServices.first;
        final created = TypedCareRequest(
          id: 'demo-req-${DateTime.now().millisecondsSinceEpoch}',
          status: bookingMode == 'SCHEDULED'
              ? 'SCHEDULED'
              : (bookingMode == 'OPEN' ? 'OPEN_FOR_PROPOSALS' : 'OFFERING'),
          bookingMode: bookingMode,
          priceAmount: estimate?.totalBasePrice ?? firstSvc.priceAmount,
          serviceTitle: firstSvc.titleAr,
          beneficiaryName: selectedBeneficiary?.displayName ?? 'المريض',
          addressText: fullAddress,
          scheduledAt: scheduledAt,
          patientLat: pt.latitude,
          patientLng: pt.longitude,
        );
        clearDraft();
        return created;
      }

      if (selectedBeneficiaryId == null) await loadBeneficiaries();
      final benId = selectedBeneficiaryId;
      if (benId == null || benId.isEmpty) {
        submitError = 'تعذر العثور على ملف المستفيد. أضف مستفيداً أولاً.';
        return null;
      }

      if (estimateStatus != EstimateStatus.verified) {
        await refreshEstimate(immediate: true);
        if (estimateStatus != EstimateStatus.verified) {
          submitError = 'تعذر التحقق من السعر الرسمي من الخادم. أعد المحاولة قبل التثبيت.';
          return null;
        }
      }

      final payload = <String, dynamic>{
        'beneficiaryId': benId,
        'items': [
          for (final entry in serviceQuantities.entries)
            {'serviceId': entry.key, 'quantity': entry.value},
        ],
        'latitude': pt.latitude,
        'longitude': pt.longitude,
        'accuracyMeters': accuracyMeters.round(),
        'locationSource': locationSource,
        'addressText': fullAddress.isEmpty ? 'الموقع المحدد على الخريطة' : fullAddress,
        'nonEmergencyConfirmed': true,
        if (requiresPrescription) 'prescriptionConfirmed': true,
        if (promoCode.trim().isNotEmpty) 'promoCode': promoCode.trim().toUpperCase(),
        'bookingMode': scheduledAt != null ? 'SCHEDULED' : bookingMode,
        'scheduledAt': ?scheduledAt?.toUtc().toIso8601String(),
        if (scheduledAt == null && bookingMode == 'OPEN')
          'openDurationMinutes': openDurationMinutes,
      };

      // BUG-015: Persist PendingOperation (operationId, idempotencyKey, payloadHash,
      // canonicalPayload, ownerUserId, createdAt, status) so phone reboot after lost
      // commit response deterministically replays without duplicate request creation.
      final ownerUserId = (await api.currentUserId()) ?? 'patient';
      final canonicalPayload = jsonEncode(_canonicalize(payload));
      final payloadHash = _fnv1a64Hex(canonicalPayload);
      final opStorageKey = 'pending_create_op_$ownerUserId';
      final existingRaw = await api.readLocal(opStorageKey);
      String? persistedKey;
      String? operationId;
      if (existingRaw != null && existingRaw.isNotEmpty) {
        try {
          final prev = jsonDecode(existingRaw);
          if (prev is Map &&
              prev['ownerUserId'] == ownerUserId &&
              prev['payloadHash'] == payloadHash &&
              prev['status'] == 'PENDING') {
            persistedKey = prev['idempotencyKey']?.toString();
            operationId = prev['operationId']?.toString();
          }
        } catch (_) {}
      }
      _idempotencyKey = (persistedKey != null && persistedKey.isNotEmpty)
          ? persistedKey
          : (_idempotencyKey ?? api.newIdempotencyKey());
      operationId ??= api.newIdempotencyKey();
      await api.writeLocal(
        opStorageKey,
        jsonEncode({
          'operationId': operationId,
          'idempotencyKey': _idempotencyKey,
          'payloadHash': payloadHash,
          'canonicalPayload': canonicalPayload,
          'ownerUserId': ownerUserId,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'status': 'PENDING',
        }),
      );

      final res = await api.post(
        '/v1/requests',
        payload,
        {'Idempotency-Key': _idempotencyKey!},
      );
      await api.writeLocal(opStorageKey, null);
      final reqId = '${res['id'] ?? ''}';
      final created = TypedCareRequest.fromJson(res, fullDetail: true);

      // BUG-026: Separate request creation success from staged clinical evidence upload;
      // never swallow upload errors or wipe stagedEvidence before upload succeeds.
      if (stagedEvidence != null && reqId.isNotEmpty) {
        try {
          await api.uploadClinicalEvidence(
            reqId,
            stagedEvidence!.evidenceType,
            stagedEvidence!.bytes,
            stagedEvidence!.filename,
          );
          pendingEvidenceRequestId = null;
          pendingEvidenceError = null;
        } catch (e) {
          pendingEvidenceRequestId = reqId;
          pendingEvidenceError = explainError(
            e,
            fallback: 'تم إنشاء الطلب بنجاح، لكن تعذر رفع الوصفة/التقرير. يمكنك إعادة المحاولة دون إنشاء طلب جديد.',
          );
          await _clearOrderSelectionPreserveEvidence();
          return created;
        }
      }

      await clearDraft();
      return created;
    } catch (e) {
      submitError = explainError(
        e,
        fallback: 'تعذر إرسال الطلب. تحقق من البيانات والاتصال ثم أعد المحاولة.',
      );
      return null;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<bool> retryPendingEvidenceUpload() async {
    final reqId = pendingEvidenceRequestId;
    final ev = stagedEvidence;
    if (kDemoMode || reqId == null || ev == null || uploadingPendingEvidence) return false;
    uploadingPendingEvidence = true;
    pendingEvidenceError = null;
    notifyListeners();
    try {
      await api.uploadClinicalEvidence(reqId, ev.evidenceType, ev.bytes, ev.filename);
      pendingEvidenceRequestId = null;
      stagedEvidence = null;
      return true;
    } catch (e) {
      pendingEvidenceError = explainError(e, fallback: 'تعذر رفع المستند السريري، أعد المحاولة');
      return false;
    } finally {
      uploadingPendingEvidence = false;
      notifyListeners();
    }
  }

  Future<void> _clearOrderSelectionPreserveEvidence() async {
    _estimateDebounce?.cancel();
    _estimateGeneration++;
    serviceQuantities.clear();
    promoCode = '';
    promoFeedback = null;
    estimate = null;
    estimateStatus = EstimateStatus.stale;
    bookingMode = 'INSTANT';
    scheduledAt = null;
    prescriptionConfirmed = false;
    _idempotencyKey = null;
    submitError = null;
    await api.writeLocal(_draftStorageKey, null);
    notifyListeners();
  }

  Future<void> clearDraft() async {
    _estimateDebounce?.cancel();
    _estimateGeneration++;
    serviceQuantities.clear();
    promoCode = '';
    promoFeedback = null;
    estimate = null;
    estimateStatus = EstimateStatus.stale;
    bookingMode = 'INSTANT';
    scheduledAt = null;
    stagedEvidence = null;
    pendingEvidenceRequestId = null;
    pendingEvidenceError = null;
    prescriptionConfirmed = false;
    _idempotencyKey = null;
    submitError = null;
    await api.writeLocal(_draftStorageKey, null);
    notifyListeners();
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    super.dispose();
  }

  Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonicalize(value[k])};
    }
    if (value is List) {
      return value.map(_canonicalize).toList();
    }
    return value;
  }

  String _fnv1a64Hex(String input) {
    var hash = BigInt.parse('14695981039346656037');
    final prime = BigInt.parse('1099511628211');
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(input)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
