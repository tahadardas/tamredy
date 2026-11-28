import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'pending_clinical_upload_store.dart';
import 'pending_request_operation_store.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../catalog/catalog_store.dart';

enum EstimateStatus { verified, unavailable, stale }

class RegionArea {
  final String governorate;
  final String name;
  final double? lat;
  final double? lng;
  const RegionArea({
    required this.governorate,
    required this.name,
    this.lat,
    this.lng,
  });
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
    if (building != null && building!.trim().isNotEmpty)
      'البناء ${building!.trim()}',
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

  BookingDraftStore({
    required this.api,
    required this.catalog,
    PendingClinicalUploadStore? clinicalUploads,
  }) {
    _clinicalUploads = clinicalUploads ?? PendingClinicalUploadStore(api: api);
    _requestOperations = PendingRequestOperationStore(api);
  }

  late final PendingClinicalUploadStore _clinicalUploads;
  late final PendingRequestOperationStore _requestOperations;
  int _sessionGeneration = 0;
  CancelToken _sessionReads = CancelToken();
  String? _ownerUserId;
  bool hasUnresolvedRequest = false;
  bool recoveringRequest = false;
  TypedCareRequest? recoveredRequest;
  String? prerequisitesError;

  void _requireCurrent(int generation) {
    if (generation != _sessionGeneration) throw StateError('Session changed');
  }

  Future<String> _authenticatedOwner(int generation) async {
    final owner = await api.currentUserId();
    _requireCurrent(generation);
    if (owner == null || owner.isEmpty) {
      throw StateError('يلزم تسجيل الدخول قبل حفظ أو إرسال الطلب.');
    }
    _ownerUserId = owner;
    return owner;
  }

  String _draftKey(String owner) => '${_draftStorageKey}_$owner';

  // Step 1: Services & pricing
  final Map<String, int> serviceQuantities = {};
  String promoCode = '';
  String? promoFeedback;
  CatalogEstimateResult? estimate;
  EstimateStatus estimateStatus = EstimateStatus.stale;
  int _estimateGeneration = 0;
  Timer? _estimateDebounce;
  Completer<void>? _estimateWaiter;
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

  String get fullAddress => [
    addressLabel.trim(),
    addressDetails.trim(),
  ].where((e) => e.isNotEmpty).join(' • ');

  Future<void> restoreDraft() async {
    final generation = _sessionGeneration;
    try {
      final owner = await _authenticatedOwner(generation);
      // Legacy drafts were not owner scoped. Never import them into an account.
      await api.writeLocal(_draftStorageKey, null);
      final operation = await _requestOperations.read(owner);
      _requireCurrent(generation);
      hasUnresolvedRequest =
          operation != null && operation['status'] != 'RECONCILED';
      await _restorePendingEvidence(owner, generation);
      final raw = await api.readLocal(_draftKey(owner));
      _requireCurrent(generation);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final items = decoded['quantities'];
      if (items is Map) {
        serviceQuantities
          ..clear()
          ..addEntries(
            items.entries
                .map(
                  (e) => MapEntry(
                    '${e.key}',
                    (num.tryParse('${e.value}') ?? 1).toInt().clamp(1, 10),
                  ),
                )
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
      openDurationMinutes =
          (num.tryParse('${decoded['openDurationMinutes'] ?? 60}') ?? 60)
              .toInt();
      scheduledAt = DateTime.tryParse(
        '${decoded['scheduledAt'] ?? ''}',
      )?.toLocal();
      notifyListeners();
    } catch (error) {
      if (generation != _sessionGeneration) return;
      prerequisitesError = explainError(
        error,
        fallback: 'تعذر استعادة المسودة الآمنة',
      );
      notifyListeners();
    }
  }

  Future<void> _persistDraft() async {
    final generation = _sessionGeneration;
    try {
      final owner = await _authenticatedOwner(generation);
      final snapshot = jsonEncode({
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
      });
      _requireCurrent(generation);
      await api.writeLocal(_draftKey(owner), snapshot);
    } catch (error) {
      if (generation != _sessionGeneration) return;
      prerequisitesError = explainError(
        error,
        fallback: 'تعذر حفظ المسودة الآمنة',
      );
      notifyListeners();
    }
  }

  void _invalidateSubmissionKey() {
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
      if (!serviceQuantities.containsKey(svc.id) &&
          serviceQuantities.length >= 10) {
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

  void _cancelEstimateDebounce() {
    _estimateDebounce?.cancel();
    _estimateDebounce = null;
    final waiter = _estimateWaiter;
    _estimateWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> refreshEstimate({bool immediate = false}) async {
    _cancelEstimateDebounce();
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
      _estimateWaiter = completer;
      _estimateDebounce = Timer(const Duration(milliseconds: 280), () async {
        _estimateWaiter = null;
        try {
          await refreshEstimate(immediate: true);
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
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
      estimateStatus = result != null
          ? EstimateStatus.verified
          : EstimateStatus.unavailable;
    } catch (e) {
      if (gen != _estimateGeneration) return;
      // BUG-009: never forge a verified CatalogEstimateResult from local sums; preserve error state.
      estimate = null;
      estimateStatus = EstimateStatus.unavailable;
      if (promoCode.trim().isNotEmpty) {
        promoFeedback = explainError(
          e,
          fallback: 'تعذر التحقق من الكود أو السعر الرسمي حالياً',
        );
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
      estimateStatus = result != null
          ? EstimateStatus.verified
          : EstimateStatus.unavailable;
      if ((estimate?.promoDiscount ?? 0) > 0 ||
          estimate?.promoAppliedCode != null) {
        promoFeedback = 'تم تطبيق الكود ($code)';
      } else {
        promoFeedback = 'تم تسجيل الكود وسيُتحقق منه عند التثبيت';
      }
    } catch (e) {
      if (gen != _estimateGeneration) return;
      estimateStatus = EstimateStatus.unavailable;
      promoFeedback = explainError(
        e,
        fallback: 'رمز الخصم غير صالح أو تعذر التحقق من السعر',
      );
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
    final generation = _sessionGeneration;
    await Future.wait([
      catalog.load(),
      loadBeneficiaries(),
      loadSavedPlaces(),
      loadRegions(),
      loadSchedulingPolicy(),
    ]);
    if (generation != _sessionGeneration) return;
    if (serviceQuantities.isNotEmpty && estimate == null) {
      await refreshEstimate(immediate: true);
    }
  }

  Future<void> loadBeneficiaries() async {
    final generation = _sessionGeneration;
    if (kDemoMode) {
      if (beneficiaries.isEmpty) {
        beneficiaries = const [
          TypedBeneficiary(
            id: 'demo-ben-1',
            displayName: 'المستخدم الحالي',
            relationship: 'SELF',
          ),
        ];
      }
      selectedBeneficiaryId ??= beneficiaries.first.id;
      notifyListeners();
      return;
    }
    loadingBeneficiaries = true;
    notifyListeners();
    try {
      final rows = await api.getList(
        '/v1/beneficiaries/mine',
        cancelToken: _sessionReads,
      );
      if (generation != _sessionGeneration) return;
      beneficiaries = [
        for (final row in rows)
          if (row is Map)
            TypedBeneficiary.fromJson(Map<String, dynamic>.from(row)),
      ];
      if (beneficiaries.isNotEmpty &&
          (selectedBeneficiaryId == null ||
              !beneficiaries.any((b) => b.id == selectedBeneficiaryId))) {
        selectedBeneficiaryId = beneficiaries.first.id;
      }
    } catch (error) {
      if (generation != _sessionGeneration) return;
      prerequisitesError = explainError(
        error,
        fallback: 'تعذر تحميل المستفيدين',
      );
    } finally {
      if (generation == _sessionGeneration) {
        loadingBeneficiaries = false;
        notifyListeners();
      }
    }
  }

  Future<TypedBeneficiary?> createBeneficiary({
    required String displayName,
    String relationship = 'OTHER',
    String? gender,
    String? emergencyContactPhone,
  }) async {
    final generation = _sessionGeneration;
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
      if (emergencyContactPhone != null &&
          emergencyContactPhone.trim().isNotEmpty)
        'emergencyContactPhone': emergencyContactPhone.trim(),
      'consentConfirmed': true,
    });
    _requireCurrent(generation);
    final created = TypedBeneficiary.fromJson(res);
    beneficiaries = [created, ...beneficiaries];
    selectedBeneficiaryId = created.id;
    await _persistDraft();
    notifyListeners();
    return created;
  }

  Future<void> removeBeneficiary(String id) async {
    final generation = _sessionGeneration;
    await api.delete('/v1/beneficiaries/$id');
    _requireCurrent(generation);
    beneficiaries.removeWhere((b) => b.id == id);
    if (selectedBeneficiaryId == id) {
      selectedBeneficiaryId = beneficiaries.isEmpty
          ? null
          : beneficiaries.first.id;
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
    final generation = _sessionGeneration;
    if (kDemoMode) return;
    try {
      final rows = await api.getList(
        '/v1/patient/saved-places',
        cancelToken: _sessionReads,
      );
      if (generation != _sessionGeneration) return;
      savedPlaces = [
        for (final row in rows)
          if (row is Map)
            SavedPlaceModel.fromJson(Map<String, dynamic>.from(row)),
      ];
      // Pre-fill default place if no location set yet
      if (locationPoint == null && savedPlaces.isNotEmpty) {
        final def =
            savedPlaces.where((p) => p.isDefault).firstOrNull ??
            savedPlaces.first;
        applySavedPlace(def, persistUse: false);
      }
      notifyListeners();
    } catch (error) {
      if (generation != _sessionGeneration) return;
      prerequisitesError = explainError(
        error,
        fallback: 'تعذر تحميل العناوين المحفوظة',
      );
      notifyListeners();
    }
  }

  Future<void> applySavedPlace(
    SavedPlaceModel place, {
    bool persistUse = true,
  }) async {
    final generation = _sessionGeneration;
    SavedPlaceModel chosen = place;
    if (persistUse && !kDemoMode) {
      try {
        final res = await api.post(
          '/v1/patient/saved-places/${place.id}/use',
          {},
        );
        chosen = SavedPlaceModel.fromJson(res);
      } catch (error) {
        if (generation != _sessionGeneration) return;
        prerequisitesError = explainError(
          error,
          fallback: 'تعذر تأكيد استخدام العنوان المحفوظ',
        );
      }
    }
    _requireCurrent(generation);
    locationPoint = chosen.point;
    addressLabel = chosen.formattedAddress.isNotEmpty
        ? chosen.formattedAddress
        : chosen.label;
    addressDetails = chosen.detailsSummary;
    accuracyMeters = chosen.accuracy;
    locationSource = 'MANUAL_PIN';
    locationError = null;
    _invalidateSubmissionKey();
    await _persistDraft();
    notifyListeners();
  }

  Future<void> loadRegions() async {
    final generation = _sessionGeneration;
    if (kDemoMode) {
      regions = const [
        RegionArea(
          governorate: 'دمشق',
          name: 'المزة',
          lat: 33.5000,
          lng: 36.2500,
        ),
        RegionArea(
          governorate: 'دمشق',
          name: 'المالكي',
          lat: 33.5200,
          lng: 36.2800,
        ),
        RegionArea(
          governorate: 'دمشق',
          name: 'كفرسوسة',
          lat: 33.4930,
          lng: 36.2760,
        ),
        RegionArea(
          governorate: 'ريف دمشق',
          name: 'جرمانا',
          lat: 33.4750,
          lng: 36.3500,
        ),
      ];
      notifyListeners();
      return;
    }
    try {
      final d = await api.getMap(
        '/v1/catalog/regions',
        cancelToken: _sessionReads,
      );
      if (generation != _sessionGeneration) return;
      final list = <RegionArea>[];
      for (final g in (d['governorates'] as List? ?? const [])) {
        if (g is! Map) continue;
        final govName = '${g['name'] ?? ''}';
        for (final a in (g['areas'] as List? ?? const [])) {
          if (a is! Map) continue;
          list.add(
            RegionArea(
              governorate: govName,
              name: '${a['name'] ?? ''}',
              lat: double.tryParse('${a['lat'] ?? ''}'),
              lng: double.tryParse('${a['lng'] ?? ''}'),
            ),
          );
        }
      }
      regions = list;
      notifyListeners();
    } catch (error) {
      if (generation != _sessionGeneration) return;
      prerequisitesError = explainError(error, fallback: 'تعذر تحميل المناطق');
      notifyListeners();
    }
  }

  Future<void> loadSchedulingPolicy() async {
    final generation = _sessionGeneration;
    if (kDemoMode) return;
    try {
      final result = await api.getMap(
        '/v1/requests/scheduling',
        cancelToken: _sessionReads,
      );
      if (generation != _sessionGeneration) return;
      schedulingPolicy = result;
      notifyListeners();
    } catch (error) {
      if (generation != _sessionGeneration) return;
      prerequisitesError = explainError(
        error,
        fallback: 'تعذر تحميل سياسة المواعيد',
      );
      notifyListeners();
    }
  }

  Future<bool> captureGpsLocation() async {
    final generation = _sessionGeneration;
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
      if (generation != _sessionGeneration) return false;
      if (!enabled) {
        locationError =
            'خدمة تحديد الموقع (GPS) مغلقة على جهازك. فعّلها ثم أعد المحاولة.';
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (generation != _sessionGeneration) return false;
      if (perm == LocationPermission.deniedForever) {
        locationError =
            'تم رفض إذن الموقع نهائياً. اسمح بالوصول من إعدادات التطبيق.';
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
      if (generation != _sessionGeneration) return false;
      locationPoint = LatLng(pos.latitude, pos.longitude);
      accuracyMeters = pos.accuracy;
      locationSource = 'GPS_CONFIRMED';
      if (addressLabel.isEmpty) addressLabel = 'موقعي الحالي';
      _invalidateSubmissionKey();
      await _persistDraft();
      return true;
    } catch (_) {
      if (generation != _sessionGeneration) return false;
      locationError =
          'تعذر التقاط إشارة GPS حالياً. حدّد موقعك على الخريطة أو اختر المنطقة.';
      return false;
    } finally {
      if (generation == _sessionGeneration) {
        locatingGps = false;
        notifyListeners();
      }
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
    if ((!capabilities.scheduledVisitsEnabled && bookingMode == 'SCHEDULED') ||
        (!capabilities.openMarketplaceEnabled && bookingMode == 'OPEN')) {
      bookingMode = 'INSTANT';
      scheduledAt = null;
      _invalidateSubmissionKey();
      _persistDraft();
    }
    notifyListeners();
  }

  void setBookingMode(String mode) {
    if ((mode == 'SCHEDULED' && !capabilities.scheduledVisitsEnabled) ||
        (mode == 'OPEN' && !capabilities.openMarketplaceEnabled)) {
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
    if (submitting || recoveringRequest || serviceQuantities.isEmpty) {
      return null;
    }
    final generation = _sessionGeneration;
    if (!kDemoMode && !capabilities.ordersAccepting) {
      submitError =
          capabilities.pausedMessage ??
          'استقبال الطلبات غير متاح حالياً؛ حدّث حالة الخادم وأعد المحاولة.';
      notifyListeners();
      return null;
    }
    if ((bookingMode == 'SCHEDULED' && !capabilities.scheduledVisitsEnabled) ||
        (bookingMode == 'OPEN' && !capabilities.openMarketplaceEnabled)) {
      submitError = 'طريقة الحجز المحددة غير متاحة حالياً.';
      notifyListeners();
      return null;
    }
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
        _requireCurrent(generation);
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

      final ownerUserId = await _authenticatedOwner(generation);
      if (selectedBeneficiaryId == null) await loadBeneficiaries();
      _requireCurrent(generation);
      final benId = selectedBeneficiaryId;
      if (benId == null || benId.isEmpty) {
        submitError = 'تعذر العثور على ملف المستفيد. أضف مستفيداً أولاً.';
        return null;
      }

      if (estimateStatus != EstimateStatus.verified) {
        await refreshEstimate(immediate: true);
        _requireCurrent(generation);
        if (estimateStatus != EstimateStatus.verified) {
          submitError =
              'تعذر التحقق من السعر الرسمي من الخادم. أعد المحاولة قبل التثبيت.';
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
        'addressText': fullAddress.isEmpty
            ? 'الموقع المحدد على الخريطة'
            : fullAddress,
        'nonEmergencyConfirmed': true,
        if (requiresPrescription) 'prescriptionConfirmed': true,
        if (promoCode.trim().isNotEmpty)
          'promoCode': promoCode.trim().toUpperCase(),
        'bookingMode': scheduledAt != null ? 'SCHEDULED' : bookingMode,
        'scheduledAt': ?scheduledAt?.toUtc().toIso8601String(),
        if (scheduledAt == null && bookingMode == 'OPEN')
          'openDurationMinutes': openDurationMinutes,
      };

      final operation = await _requestOperations.begin(
        ownerUserId,
        payload,
        expectsClinicalUpload: stagedEvidence != null,
      );
      _requireCurrent(generation);
      hasUnresolvedRequest = true;
      if (stagedEvidence != null && operation['status'] == 'PENDING') {
        final evidence = stagedEvidence!;
        await _clinicalUploads.prepare(
          ownerUserId: ownerUserId,
          operationId: operation['operationId'] as String,
          evidenceType: evidence.evidenceType,
          filename: evidence.filename,
          bytes: evidence.bytes,
        );
        _requireCurrent(generation);
      }
      return await _executeOperation(ownerUserId, operation, generation);
    } catch (e) {
      if (generation != _sessionGeneration) return null;
      submitError = explainError(
        e,
        fallback:
            'تعذر إرسال الطلب. تحقق من البيانات والاتصال ثم أعد المحاولة.',
      );
      return null;
    } finally {
      if (generation == _sessionGeneration) {
        submitting = false;
        notifyListeners();
      }
    }
  }

  Future<TypedCareRequest?> recoverPendingRequest() async {
    if (recoveringRequest || submitting || kDemoMode) return null;
    final generation = _sessionGeneration;
    recoveringRequest = true;
    submitError = null;
    notifyListeners();
    try {
      final owner = await _authenticatedOwner(generation);
      final operation = await _requestOperations.read(owner);
      _requireCurrent(generation);
      if (operation == null || operation['status'] == 'RECONCILED') {
        hasUnresolvedRequest = false;
        return null;
      }
      if (operation['status'] == 'PENDING' &&
          operation['expectsClinicalUpload'] == true &&
          await _clinicalUploads.metadata(owner) == null &&
          stagedEvidence != null) {
        _requireCurrent(generation);
        final evidence = stagedEvidence!;
        await _clinicalUploads.prepare(
          ownerUserId: owner,
          operationId: operation['operationId'] as String,
          evidenceType: evidence.evidenceType,
          filename: evidence.filename,
          bytes: evidence.bytes,
        );
      }
      _requireCurrent(generation);
      return await _executeOperation(owner, operation, generation);
    } catch (error) {
      if (generation != _sessionGeneration) return null;
      submitError = explainError(
        error,
        fallback:
            'تعذر استعادة نتيجة الطلب السابق. يمكنك إعادة المحاولة بالمفتاح نفسه.',
      );
      return null;
    } finally {
      if (generation == _sessionGeneration) {
        recoveringRequest = false;
        notifyListeners();
      }
    }
  }

  Future<TypedCareRequest> _executeOperation(
    String owner,
    Map<String, dynamic> operation,
    int generation,
  ) async {
    _requireCurrent(generation);
    Map<String, dynamic> response;
    if (operation['status'] == 'CONFIRMED') {
      // Revalidate request ownership on the server after restoring a process.
      response = await api.getMap(
        '/v1/requests/${operation['requestId']}',
        cancelToken: _sessionReads,
      );
    } else {
      if (operation['expectsClinicalUpload'] == true &&
          await _clinicalUploads.metadata(owner) == null) {
        throw StateError(
          'يلزم إعادة اختيار المستند الطبي وحفظه بأمان قبل استعادة إرسال الطلب.',
        );
      }
      _requireCurrent(generation);
      final payload = Map<String, dynamic>.from(
        jsonDecode(operation['canonicalPayload'] as String) as Map,
      );
      response = await api.post('/v1/requests', payload, {
        'Idempotency-Key': operation['idempotencyKey'] as String,
      });
    }
    // Durable confirmation belongs to the original owner even if logout races
    // the HTTP response. UI state is updated only after the generation check.
    await _requestOperations.confirm(owner, operation, response);
    final requestId = '${response['id'] ?? ''}';
    final uploadMetadata = await _clinicalUploads.metadata(owner);
    final hasOwnEvidence =
        uploadMetadata?['operationId'] == operation['operationId'];
    if (hasOwnEvidence) await _clinicalUploads.bindRequest(owner, requestId);
    _requireCurrent(generation);
    final request = TypedCareRequest.fromJson(response, fullDetail: true);
    await api.writeLocal(
      'confirmed_request_$owner',
      jsonEncode({'requestId': request.id}),
    );
    _requireCurrent(generation);
    recoveredRequest = request;
    if (hasOwnEvidence) await _restorePendingEvidence(owner, generation);
    _requireCurrent(generation);
    if (pendingEvidenceRequestId == requestId) {
      await retryPendingEvidenceUpload();
      _requireCurrent(generation);
      if (pendingEvidenceRequestId != null) {
        await _clearOrderSelectionPreserveEvidence();
        await _requestOperations.reconcile(owner, requestId);
        _requireCurrent(generation);
        hasUnresolvedRequest = false;
        return request;
      }
    }
    if (uploadMetadata != null && !hasOwnEvidence) {
      await _clearOrderSelectionPreserveEvidence();
    } else {
      await clearDraft();
    }
    await _requestOperations.reconcile(owner, requestId);
    _requireCurrent(generation);
    hasUnresolvedRequest = false;
    return request;
  }

  Future<void> _restorePendingEvidence(String owner, int generation) async {
    final metadata = await _clinicalUploads.metadata(owner);
    _requireCurrent(generation);
    if (metadata == null || metadata['requestId'] == null) return;
    final requestId = metadata['requestId'] as String;
    final request = await api.getMap(
      '/v1/requests/$requestId',
      cancelToken: _sessionReads,
    );
    _requireCurrent(generation);
    // GET validates ownership. A terminal/approved request is not re-uploaded.
    final clinicalStatus =
        request['clinicalApprovalStatus'] ??
        request['clinical_approval_status'];
    final status = request['status'];
    pendingEvidenceRequestId = requestId;
    if (!const ['PENDING', 'REJECTED'].contains(clinicalStatus) ||
        const [
          'COMPLETED',
          'CANCELLED',
          'EXPIRED',
          'FAILED',
          'UNFULFILLED',
          'ESCALATED',
        ].contains(status)) {
      pendingEvidenceError =
          'الطلب لم يعد يقبل مستندات طبية؛ يلزم مراجعة حالة الطلب.';
      stagedEvidence = null;
      return;
    }
    final bytes = await _clinicalUploads.readBytes(owner);
    _requireCurrent(generation);
    stagedEvidence = StagedEvidence(
      evidenceType: metadata['evidenceType'] as String,
      filename: metadata['filename'] as String,
      bytes: bytes,
    );
    pendingEvidenceError =
        'يوجد مستند طبي محفوظ بأمان لهذا الطلب. يمكنك إعادة رفعه دون إنشاء طلب جديد.';
  }

  Future<bool> retryPendingEvidenceUpload() async {
    final reqId = pendingEvidenceRequestId;
    if (kDemoMode || reqId == null || uploadingPendingEvidence) return false;
    final generation = _sessionGeneration;
    uploadingPendingEvidence = true;
    pendingEvidenceError = null;
    notifyListeners();
    try {
      final owner = await _authenticatedOwner(generation);
      await _restorePendingEvidence(owner, generation);
      _requireCurrent(generation);
      final evidence = stagedEvidence;
      if (evidence == null || pendingEvidenceRequestId != reqId) return false;
      await _clinicalUploads.markAttempt(owner, failed: false);
      _requireCurrent(generation);
      await api.uploadClinicalEvidence(
        reqId,
        evidence.evidenceType,
        evidence.bytes,
        evidence.filename,
      );
      // Keep cleanup tied to the original owner even if the account changed.
      await _clinicalUploads.complete(owner);
      _requireCurrent(generation);
      pendingEvidenceRequestId = null;
      pendingEvidenceError = null;
      stagedEvidence = null;
      return true;
    } catch (error) {
      if (generation != _sessionGeneration) return false;
      final owner = _ownerUserId;
      if (owner != null && await _clinicalUploads.metadata(owner) != null) {
        await _clinicalUploads.markAttempt(owner, failed: true);
      }
      if (generation != _sessionGeneration) return false;
      pendingEvidenceError = explainError(
        error,
        fallback: 'تعذر رفع المستند السريري، أعد المحاولة',
      );
      return false;
    } finally {
      if (generation == _sessionGeneration) {
        uploadingPendingEvidence = false;
        notifyListeners();
      }
    }
  }

  Future<void> _clearOrderSelectionPreserveEvidence() async {
    _cancelEstimateDebounce();
    _estimateGeneration++;
    serviceQuantities.clear();
    promoCode = '';
    promoFeedback = null;
    estimate = null;
    estimateStatus = EstimateStatus.stale;
    bookingMode = 'INSTANT';
    scheduledAt = null;
    prescriptionConfirmed = false;
    submitError = null;
    final owner = _ownerUserId;
    if (owner != null) await api.writeLocal(_draftKey(owner), null);
    notifyListeners();
  }

  Future<void> clearDraft() async {
    _cancelEstimateDebounce();
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
    submitError = null;
    final owner = _ownerUserId;
    if (owner != null) await api.writeLocal(_draftKey(owner), null);
    notifyListeners();
  }

  /// Destroy in-memory account state synchronously before awaiting logout.
  /// Durable unresolved operations stay encrypted and scoped to their owner.
  void resetForSessionChange() {
    _sessionGeneration++;
    _estimateGeneration++;
    _sessionReads.cancel('session_changed');
    _sessionReads = CancelToken();
    _cancelEstimateDebounce();
    _ownerUserId = null;
    beneficiaries = [];
    selectedBeneficiaryId = null;
    loadingBeneficiaries = false;
    savedPlaces = [];
    regions = [];
    locationPoint = null;
    accuracyMeters = 0;
    addressLabel = '';
    addressDetails = '';
    locationSource = 'MANUAL_PIN';
    locationError = null;
    locatingGps = false;
    stagedEvidence = null;
    pendingEvidenceRequestId = null;
    pendingEvidenceError = null;
    uploadingPendingEvidence = false;
    serviceQuantities.clear();
    promoCode = '';
    promoFeedback = null;
    estimate = null;
    estimating = false;
    estimateStatus = EstimateStatus.stale;
    bookingMode = 'INSTANT';
    openDurationMinutes = 60;
    scheduledAt = null;
    schedulingPolicy = null;
    prescriptionConfirmed = false;
    submitting = false;
    recoveringRequest = false;
    recoveredRequest = null;
    hasUnresolvedRequest = false;
    prerequisitesError = null;
    submitError = null;
    capabilities = const ServerCapabilities(ordersAccepting: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionGeneration++;
    _sessionReads.cancel('disposed');
    _cancelEstimateDebounce();
    super.dispose();
  }
}
