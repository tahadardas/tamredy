import 'dart:async';
import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:uuid/uuid.dart';

enum ServiceLoadState { initial, loading, loaded, empty, networkError, serverError }

class ServiceItem {
  final String id, title, subtitle, note;
  final int price;
  final int iconCode; // 0: injection, 1: wound care, 2: vitals, 3: elderly/home
  final bool needsConfirmation;
  final bool requiresPrescription;
  final String code;
  final int expectedMinutes;
  final PricingRule rule;
  const ServiceItem(
    this.id,
    this.title,
    this.subtitle,
    this.note,
    this.price,
    this.iconCode, {
    this.needsConfirmation = false,
    this.requiresPrescription = false,
    this.code = '',
    this.expectedMinutes = 30,
    this.rule = const PricingRule(basePrice: 0),
  });

  /// Live catalogue row from `/v1/services` (admin-managed).
  factory ServiceItem.fromApi(Map<String, dynamic> j, int index) {
    final rule = PricingRule.fromService(j);
    final desc = (j['description_ar'] ?? '').toString();
    final code = (j['code'] ?? '').toString().toUpperCase();
    final reqPrescription = j['requires_prescription'] == true;
    final expMin = (num.tryParse('${j['expected_minutes']}') ?? 30).toInt();

    // Explicit icon mapping based on service code instead of arbitrary array order
    int iconIdx = 0;
    if (code.contains('INJ') || code.contains('MED') || code.contains('VACC')) {
      iconIdx = 0;
    } else if (code.contains('WOUND') || code.contains('DRESS') || code.contains('SUTURE')) {
      iconIdx = 1;
    } else if (code.contains('VITAL') || code.contains('MONITOR') || code.contains('PRESSURE')) {
      iconIdx = 2;
    } else if (code.contains('ELDER') || code.contains('HOME') || code.contains('CARE')) {
      iconIdx = 3;
    } else {
      iconIdx = index % 4;
    }

    return ServiceItem(
      '${j['id']}',
      '${j['title_ar']}',
      desc.isEmpty ? (reqPrescription ? 'بوصفة طبية' : 'خدمة تمريضية') : desc,
      desc.isEmpty ? 'تُنفذها كوادر تمريضية معتمدة وفق أعلى معايير الجودة والسلامة.' : desc,
      rule.basePrice,
      iconIdx,
      needsConfirmation: reqPrescription,
      requiresPrescription: reqPrescription,
      code: code,
      expectedMinutes: expMin,
      rule: rule,
    );
  }
}

class HistoryItem {
  final String title, date;
  final int price;
  final String status; // مكتملة / ملغاة
  final String? requestId;
  const HistoryItem(this.title, this.date, this.price, this.status, {this.requestId});
}

class WalletTx {
  final String title, sub;
  final int amount;
  const WalletTx(this.title, this.sub, this.amount);
}

enum VisitStage { none, scheduled, interrupted, searching, openMarketplace, assigned, enRoute, arrived, inService, completed, unfulfilled }

const List<ServiceItem> kSampleServices = [
  ServiceItem(
    'inj',
    'حقن وعلاجات',
    'بوصفة طبية',
    'يُنفذها ممرض مخول بعد التحقق من الوصفة والتعليمات الطبية.',
    900,
    0,
    needsConfirmation: true,
    rule: PricingRule(
      basePrice: 900,
      includedMinutes: 20,
      blockMinutes: 10,
      blockPrice: 300,
      expectedMinutes: 20,
      roundingStep: 50,
    ),
  ),
  ServiceItem(
    'dress',
    'تغيير ضماد',
    'متابعة الجروح',
    'يُنفذها ممرض مخول بعد التحقق من الحالة والتعليمات الطبية المطلوبة.',
    1200,
    1,
    needsConfirmation: true,
    rule: PricingRule(
      basePrice: 1200,
      includedMinutes: 30,
      blockMinutes: 15,
      blockPrice: 400,
      expectedMinutes: 40,
      roundingStep: 50,
    ),
  ),
  ServiceItem(
    'vitals',
    'متابعة منزلية',
    'علامات حيوية',
    'قياس العلامات الحيوية ومتابعة الحالة العامة في المنزل.',
    1200,
    2,
    rule: PricingRule(
      basePrice: 1200,
      includedMinutes: 30,
      blockMinutes: 15,
      blockPrice: 400,
      expectedMinutes: 30,
      roundingStep: 50,
    ),
  ),
  ServiceItem(
    'elder',
    'رعاية كبار السن',
    'زيارات ورديات',
    'رعاية تمريضية غير طبية لكبار السن في المنزل.',
    1800,
    3,
    rule: PricingRule(
      basePrice: 1800,
      includedMinutes: 60,
      blockMinutes: 30,
      blockPrice: 800,
      expectedMinutes: 60,
      roundingStep: 50,
    ),
  ),
];

/// Patient app state. In demo mode a timer simulates the dispatch lifecycle;
/// otherwise the real API (`/v1/...`) is used.
class PatientController extends ChangeNotifier {
  final TamreedyApi api = TamreedyApi();
  int tab = 0;

  List<ServiceItem> services = !kDemoMode ? const [] : kSampleServices;
  List<HistoryItem> history = !kDemoMode ? const [] : const [
    HistoryItem('العناية بالجروح', '20 نوفمبر 2026', 1200, 'مكتملة'),
    HistoryItem('زيارة علامات حيوية', '18 نوفمبر 2026', 900, 'مكتملة'),
    HistoryItem('رعاية منزلية', '12 نوفمبر 2026', 0, 'ملغاة'),
  ];
  List<WalletTx> txs = !kDemoMode ? const [] : const [
    WalletTx('إرجاع باقي نقدي', 'اليوم • استرداد مؤكد', 300),
    WalletTx('دفع زيارة', 'أمس • مكتملة', -1200),
    WalletTx('شحن المحفظة', 'قبل يومين', 5000),
  ];
  int balance = kDemoMode ? 5000 : 0;

  ServiceItem? service;
  final Map<String, int> selectedServiceQuantities = {};
  String beneficiary = kDemoMode ? 'والدي - أحمد' : '';
  String address = '';
  String extraAddress = '';
  String notes = '';
  LatLng? position; // confirmed visit location
  double accuracy = 30;
  LatLng? nursePos;
  RouteInfo? route;
  int _pollCount = 0;
  Timer? _demoMove;
  DateTime? _searchStart;
  String payMethod = kDemoMode ? 'wallet' : 'cash'; // wallet | cash | mixed
  int rating = 5;

  // Price estimate + promo
  String promoCode = '';
  Promo? promo;
  String? promoMsg;
  PriceEstimate? est;
  // Bill (real or demo) once the nurse closes the visit
  BillInfo? bill;
  // Marketing consent (default off) and the "top nurse" badge from tracking
  bool marketingOptIn = false;
  Map<String, dynamic>? nurseBadge;
  // Extra estimate info from the server: night/holiday surcharge applied now, tax, travel-fee rules
  Map<String, dynamic> quoteInfo = {};
  // Personal referral code summary (`/v1/referral/mine`)
  Map<String, dynamic>? referral;

  VisitStage stage = VisitStage.none;
  String? requestId;
  DateTime? scheduledAt;
  String? _idemKey;
  Timer? _timer;
  bool busy = false;
  String? error;

  // Smart Booking & Open Marketplace
  String bookingMode = 'INSTANT';
  String? marketplaceStatus;
  String? clinicalApprovalStatus;
  int activeProposalsCount = 0;
  DateTime? openExpiresAt;

  ServiceLoadState serviceState = kDemoMode ? ServiceLoadState.loaded : ServiceLoadState.initial;
  String? serviceError;

  List<({String id, String name})> beneficiaries = [];
  String? selectedBeneficiaryId;

  Future<void> loadBeneficiary() async {
    if (kDemoMode) return;
    try {
      final rows = await api.getList('/v1/beneficiaries/mine');
      beneficiaries = [
        for (final row in rows.cast<Map>())
          (id: row['id'] as String, name: row['display_name'] as String),
      ];
      if (!beneficiaries.any((entry) => entry.id == selectedBeneficiaryId)) {
        selectedBeneficiaryId = beneficiaries.firstOrNull?.id;
      }
      beneficiary = beneficiaries.where((entry) => entry.id == selectedBeneficiaryId).firstOrNull?.name ?? '';
      notifyListeners();
    } catch (_) {
      // Retain the most recent server list during a transient failure.
    }
  }

  void selectBeneficiary(String id) {
    final selected = beneficiaries.where((entry) => entry.id == id).firstOrNull;
    if (selected == null) return;
    selectedBeneficiaryId = selected.id;
    beneficiary = selected.name;
    notifyListeners();
  }

  /// Live catalogue: services and prices the admin edits appear/disappear here without an app update.
  Future<void> loadServices() async {
    serviceState = ServiceLoadState.loading;
    serviceError = null;
    notifyListeners();
    try {
      final list = await api.getList('/v1/services');
      services = [
        for (var i = 0; i < list.length; i++)
          ServiceItem.fromApi(Map<String, dynamic>.from(list[i] as Map), i),
      ];
      if (service != null && !services.any((s) => s.id == service!.id)) {
        service = null; // removed by admin
      }
      selectedServiceQuantities.removeWhere((id, _) => !services.any((s) => s.id == id));
      serviceState = services.isEmpty ? ServiceLoadState.empty : ServiceLoadState.loaded;
      notifyListeners();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        serviceState = ServiceLoadState.networkError;
        serviceError = 'تعذر الاتصال بالخادم. تأكد من اتصال الإنترنت ثم أعد المحاولة.';
      } else {
        serviceState = ServiceLoadState.serverError;
        serviceError = 'حدث خطأ أثناء تحميل الخدمات (${e.response?.statusCode ?? 'شبكة'}).';
      }
      notifyListeners();
    } catch (e) {
      serviceState = ServiceLoadState.serverError;
      serviceError = 'حدث خطأ غير متوقع أثناء استرجاع الخدمات: $e';
      notifyListeners();
    }
  }

  /// Realtime hook: the server tells every app when the catalogue, request, or payment changed.
  void onLive(String type) {
    if (type == 'catalog.changed') {
      loadServices();
    } else {
      resync();
    }
  }

  // ---- promo codes ----
  static const _demoPromos = {
    'WELCOME20': Promo('WELCOME20', percent: true, value: 20, maxDiscount: 500),
  };

  /// Live estimate from the server (includes surcharges that apply right now and tax).
  Future<void> _quote() async {
    final sid = service?.id;
    if (sid == null) return;
    try {
      final q = await api.post('/v1/pricing/quote', {
        'serviceId': sid,
        if (promoCode.isNotEmpty) 'promoCode': promoCode,
      });
      est = PriceEstimate(
        (num.parse('${q['min']}')).round(),
        (num.parse('${q['expected']}')).round(),
      );
      quoteInfo = q;
      notifyListeners();
    } catch (_) {
      /* keep the local estimate */
    }
  }

  void _recalc() {
    if (service != null) est = estimatePrice(service!.rule, promo);
  }

  Future<void> applyPromo(String code) async {
    code = code.trim().toUpperCase();
    promoMsg = null;
    if (code.isEmpty) {
      promo = null;
      promoCode = '';
      _recalc();
      notifyListeners();
      return;
    }
    if (kDemoMode) {
      final p = _demoPromos[code];
      promo = p;
      promoCode = p == null ? '' : code;
      promoMsg = p == null ? 'الكود غير صحيح' : 'تم تطبيق الخصم';
      _recalc();
    } else {
      try {
        final q = await api.post('/v1/pricing/quote', {
          'serviceId': service!.id,
          'promoCode': code,
        });
        promoCode = code;
        est = PriceEstimate(
          (num.parse('${q['min']}')).round(),
          (num.parse('${q['expected']}')).round(),
        );
        quoteInfo = q;
        promoMsg = 'تم تطبيق الخصم';
      } on DioException catch (e) {
        promoCode = '';
        promo = null;
        _recalc();
        promoMsg = _promoError((e.response?.data as Map?)?['code']);
      }
    }
    Analytics.log('promo_applied', {'ok': promoCode.isEmpty ? 0 : 1});
    notifyListeners();
  }

  /// "I installed the app and have the company code": saved once, applied to the next order automatically.
  Future<String> claimCode(String code) async {
    code = code.trim().toUpperCase();
    if (kDemoMode) {
      final p = _demoPromos[code];
      if (p == null) return 'الكود غير صحيح';
      promo = p;
      promoCode = code;
      _recalc();
      notifyListeners();
      return 'تم حفظ الكود — سيُطبَّق على طلبك القادم';
    }
    try {
      await api.post('/v1/promos/claim', {'code': code});
      Analytics.log('promo_claimed');
      return 'تم حفظ الكود — سيُطبَّق على طلبك القادم';
    } on DioException catch (e) {
      return _promoError((e.response?.data as Map?)?['code']);
    }
  }

  static String _promoError(Object? c) => switch ('$c') {
    'PROMO_NOT_FOUND' => 'الكود غير صحيح',
    'PROMO_EXPIRED' => 'انتهت صلاحية الكود',
    'PROMO_NOT_STARTED' => 'الكود لم يبدأ بعد',
    'PROMO_INACTIVE' => 'الكود غير مفعّل',
    'PROMO_EXHAUSTED' => 'استُنفد عدد استخدامات الكود',
    'PROMO_ALREADY_USED' => 'استخدمتَ هذا الكود من قبل',
    'PROMO_FIRST_ORDER_ONLY' => 'الكود صالح للطلب الأول فقط',
    'PROMO_NOT_FOR_SERVICE' => 'الكود لا يشمل هذه الخدمة',
    'PROMO_MIN_AMOUNT' => 'قيمة الطلب أقل من الحد الأدنى للكود',
    _ => 'تعذر تطبيق الكود',
  };

  // ---- bill ----
  Future<bool> loadBill() async {
    final id = requestId;
    if (id == null) return false;
    if (kDemoMode) {
      bill ??= _demoBill();
    } else {
      try {
        final updated = BillInfo.fromJson(
          await api.getMap('/v1/requests/$id/bill'),
        );
        if (id != requestId) return false;
        bill = updated;
      } catch (_) {
        return false;
      }
    }
    notifyListeners();
    return true;
  }

  BillInfo _demoBill() {
    final b = finalBill(service!.rule, 47 * 60, promo);
    return BillInfo(
      due: b.due,
      minutes: b.minutes,
      gross: b.gross,
      discount: b.discount,
      collected: 0,
      remaining: b.due,
      status: 'DUE',
      promoCode: promo?.code,
    );
  }

  /// Optional tip: added to the cash handed to the nurse (100% hers).
  Future<void> setTip(int amount) async {
    final b = bill;
    if (b == null) return;
    if (kDemoMode) {
      bill = BillInfo(
        due: b.due,
        minutes: b.minutes,
        gross: b.gross,
        discount: b.discount,
        collected: b.collected,
        remaining: b.due + amount - b.collected,
        status: b.status,
        promoCode: b.promoCode,
        tip: amount,
      );
    } else {
      try {
        final key = 'tip:$requestId:$amount';
        await api.post('/v1/requests/$requestId/tip', {'amount': amount}, {
          'Idempotency-Key': key,
        });
        await loadBill();
      } on DioException catch (e) {
        promoMsg = ((e.response?.data as Map?)?['code']) == 'ALREADY_PAID'
            ? 'تم الدفع مسبقًا'
            : 'تعذر إضافة الإكرامية';
      }
    }
    Analytics.log('tip_selected', {'amount': amount});
    notifyListeners();
  }

  Future<void> loadConsent() async {
    if (kDemoMode) return;
    try {
      marketingOptIn =
          (await api.getMap('/v1/me/marketing-consent'))['optIn'] == true;
      notifyListeners();
    } catch (_) {}
  }

  /// Marketing notifications and offers only after the patient agrees (can be withdrawn any time).
  Future<void> setConsent(bool v) async {
    marketingOptIn = v;
    notifyListeners();
    Analytics.log('marketing_consent', {'granted': v ? 1 : 0});
    if (kDemoMode) return;
    try {
      await api.put('/v1/me/marketing-consent', {'optIn': v});
    } catch (_) {
      marketingOptIn = !v;
      notifyListeners();
    }
  }

  Future<void> loadReferral() async {
    if (kDemoMode) {
      referral = {
        'enabled': true,
        'code': 'TMDEMO12',
        'invited': 3,
        'rewarded': 1,
        'friendGets': 15,
        'youGet': 15,
        'maxDiscount': 1000,
        'alreadyReferred': false,
      };
    } else {
      try {
        referral = await api.getMap('/v1/referral/mine');
      } catch (_) {
        /* shown as unavailable */
      }
    }
    notifyListeners();
  }

  /// A new user enters a friend's code before the first order.
  Future<String> claimReferral(String code) async {
    code = code.trim().toUpperCase();
    if (kDemoMode) {
      return code == 'TMDEMO12'
          ? 'تم! خصم 15% على طلبك الأول'
          : 'الكود غير صحيح';
    }
    try {
      final r = await api.post('/v1/referral/claim', {'code': code});
      Analytics.log('referral_claimed');
      await loadReferral();
      return 'تم! خصم ${r['discountPercent']}% على طلبك الأول';
    } on DioException catch (e) {
      return switch ('${(e.response?.data as Map?)?['code']}') {
        'REFERRAL_CODE_NOT_FOUND' => 'الكود غير صحيح',
        'REFERRAL_OWN_CODE' => 'لا يمكنك استخدام كودك الشخصي',
        'REFERRAL_ALREADY_USED' => 'سبق أن أدخلتَ كود صديق',
        'REFERRAL_ONLY_BEFORE_FIRST_ORDER' => 'كود الدعوة يُدخَل قبل أول طلب',
        'REFERRAL_DISABLED' => 'برنامج الدعوة غير مفعّل حاليًا',
        _ => 'تعذر تطبيق الكود',
      };
    }
  }

  Future<void> submitRating() async {
    Analytics.log('rating_submitted', {'stars': rating});
    final visit = bill?.visitId;
    if (kDemoMode || visit == null) return;
    try {
      await api.post('/v1/visits/$visit/patient-review', {'stars': rating});
    } catch (_) {
      /* review window is 48h; the user can retry from history later */
    }
  }

  String? historyError;

  /// Real visit history from `/v1/requests/mine` (keyset-paged; first page).
  Future<void> loadHistory() async {
    try {
      final page = await api.getMap('/v1/requests/mine');
      history = [
        for (final r in (page['items'] as List))
          HistoryItem(
            '${(r as Map)['service_title']}',
            '${r['created_at']}'.split('T').first,
            r['status'] == 'COMPLETED'
                ? (num.tryParse('${r['price_amount']}') ?? 0).round()
                : 0,
            requestStatusAr('${r['status']}'),
            requestId: r['id'] as String?,
          ),
      ];
      historyError = null;
      notifyListeners();
    } catch (_) {
      historyError = 'تعذر تحميل السجل من الخادم';
      notifyListeners();
    }
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
    if (!kDemoMode && i == 1) loadHistory();
  }

  void pick(ServiceItem s) {
    service = s;
    selectedServiceQuantities
      ..clear()
      ..[s.id] = 1;
    quoteInfo = {};
    promo = null;
    promoCode = '';
    promoMsg = null;
    _recalc();
    if (!kDemoMode) _quote();
    Analytics.log('service_selected', {'service_id': s.id});
    notifyListeners();
  }

  /// Logic-only multi-service selection API used by the booking UI without coupling
  /// the controller to a particular visual design.
  void setServiceQuantity(ServiceItem item, int quantity) {
    if (quantity < 0 || quantity > 10) return;
    if (quantity == 0) {
      selectedServiceQuantities.remove(item.id);
      if (service?.id == item.id) {
        service = selectedServiceQuantities.isEmpty
            ? null
            : services.where((candidate) => candidate.id == selectedServiceQuantities.keys.first).firstOrNull;
      }
    } else {
      if (!selectedServiceQuantities.containsKey(item.id) && selectedServiceQuantities.length >= 10) return;
      selectedServiceQuantities[item.id] = quantity;
      service ??= item;
    }
    promo = null;
    promoMsg = null;
    notifyListeners();
  }

  void setPay(String m) {
    payMethod = m;
    Analytics.log('payment_method_selected', {'method': m});
    notifyListeners();
  }

  void setRating(int r) {
    rating = r;
    Analytics.log('rating_selected', {'stars': r});
    notifyListeners();
  }

  /// Center the picker on the device location.
  Future<void> useCurrentLocation({
    void Function(LatLng point, String label, double accuracy)? onLocated,
  }) async {
    final apply = onLocated ?? (point, label, accuracy) =>
        selectVisitLocation(point, label, accuracyMeters: accuracy);
    error = null;
    if (kDemoMode) {
      apply(kDamascus, 'موقعي الحالي', 0);
      return;
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        error = 'خدمة تحديد الموقع (GPS) مغلقة على جهازك. يُرجى تفعيلها أولاً للمتابعة.';
        notifyListeners();
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.deniedForever) {
        error = 'تم رفض إذن الموقع بشكل دائم. يُرجى السماح به من إعدادات التطبيق.';
        notifyListeners();
        return;
      }
      if (p == LocationPermission.denied) {
        error = 'يرجى السماح بالوصول إلى الموقع لتحديد مكان الزيارة بدقة.';
        notifyListeners();
        return;
      }
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      apply(LatLng(fix.latitude, fix.longitude), 'موقعي الحالي', fix.accuracy);
      return;
    } catch (_) {
      error = 'تعذر تحديد موقعك الحالي. تأكد من تفعيل الـ GPS أو اختر منطقتك من القائمة.';
    }
    notifyListeners();
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  void selectVisitLocation(
    LatLng point,
    String label, {
    double accuracyMeters = 0,
    String addressDetails = '',
  }) {
    position = point;
    address = label;
    accuracy = accuracyMeters;
    extraAddress = addressDetails;
    notifyListeners();
  }

  void setPicked(LatLng point, String resolvedAddress) {
    if (position != point) {
      position = point;
      address = 'الموقع المحدد على الخريطة';
      accuracy = 0;
    }
    if (resolvedAddress.isNotEmpty) address = resolvedAddress;
    notifyListeners();
  }

  String get visitAddress =>
      [address, extraAddress.trim()].where((part) => part.isNotEmpty).join(' • ');

  /// Creates the request, then follows its lifecycle.
  Future<bool> submit({DateTime? appointment}) async {
    if (service == null || selectedServiceQuantities.isEmpty || busy) return false;
    _searchStart = DateTime.now();
    Analytics.log('request_submitted', {
      'service_id': service!.id,
      'value': service!.price,
      'currency': 'SYP',
    });
    busy = true;
    error = null;
    notifyListeners();
    if (kDemoMode) {
      requestId = 'demo-1052';
      stage = VisitStage.searching;
      _timer?.cancel();
      var step = 0;
      _timer = Timer.periodic(const Duration(seconds: 4), (t) {
        step++;
        stage = const [
          VisitStage.searching,
          VisitStage.enRoute,
          VisitStage.arrived,
          VisitStage.inService,
          VisitStage.completed,
        ][step.clamp(0, 4)];
        if (stage == VisitStage.enRoute) _startDemoMove();
        if (stage != VisitStage.enRoute) {
          _demoMove?.cancel();
          nursePos = null;
        }
        _logStage();
        if (stage == VisitStage.completed) {
          t.cancel();
          bill = _demoBill();
        }
        notifyListeners();
      });
      busy = false;
      notifyListeners();
      return true;
    }
    final visitPoint = position;
    final confirmedAddress = visitAddress;
    final accuracyMeters = accuracy.round();
    if (visitPoint == null) {
      busy = false;
      error = 'يلزم تأكيد الموقع قبل الإرسال';
      notifyListeners();
      return false;
    }
    try {
      _idemKey ??= const Uuid().v4();
      if (selectedBeneficiaryId == null) await loadBeneficiary();
      final beneficiaryId = selectedBeneficiaryId;
      if (beneficiaryId == null) {
        error = 'تعذر تحديد المستفيد. تحقق من بيانات الحساب وحاول مجددًا.';
        return false;
      }
      final r = await api.post(
        '/v1/requests',
        {
          'beneficiaryId': beneficiaryId,
          if (appointment != null) 'scheduledAt': appointment.toUtc().toIso8601String(),
          'items': [
            for (final entry in selectedServiceQuantities.entries)
              {'serviceId': entry.key, 'quantity': entry.value},
          ],
          'latitude': visitPoint.latitude,
          'longitude': visitPoint.longitude,
          'accuracyMeters': accuracyMeters,
          'locationSource': 'MANUAL_PIN',
          'addressText': confirmedAddress,
          'nonEmergencyConfirmed': true,
          if (service!.requiresPrescription) 'prescriptionConfirmed': true,
          if (promoCode.isNotEmpty) 'promoCode': promoCode,
          'bookingMode': bookingMode,
          if (bookingMode == 'OPEN') 'openDurationMinutes': 60,
        },
        {'Idempotency-Key': _idemKey!},
      );
      requestId = r['id'] as String?;
      clinicalApprovalStatus = (r['clinicalApprovalStatus'] ?? r['clinical_approval_status']) as String?;
      position = visitPoint;
      address = confirmedAddress;
      accuracy = accuracyMeters.toDouble();
      extraAddress = '';
      _idemKey = null;
      scheduledAt = appointment;
      stage = r['status'] == 'SCHEDULED'
          ? VisitStage.scheduled
          : (bookingMode == 'OPEN' || r['marketplace_status'] == 'OPEN_FOR_PROPOSALS')
              ? VisitStage.openMarketplace
              : VisitStage.searching;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
      return true;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر إنشاء الطلب. تحقق من الخدمة والموقع وحاول مرة أخرى');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Restores active care request from server on app startup or reconnect.
  Future<void> restoreActiveRequest() async {
    if (kDemoMode || busy || requestId != null) return;
    try {
      final res = await api.getMap('/v1/me/active-request');
      if (busy || requestId != null) return;
      if (res['hasActive'] == true && res['request'] != null) {
        final req = Map<String, dynamic>.from(res['request'] as Map);
        requestId = req['id']?.toString();
        clinicalApprovalStatus = req['clinical_approval_status'] as String?;
        final status = '${req['status']}';
        scheduledAt = DateTime.tryParse('${req['scheduled_at'] ?? req['scheduledAt']}')?.toLocal();
        address = req['address_text']?.toString() ?? 'الموقع المحدد على الخريطة';
        extraAddress = '';
        if (req['patient_lat'] != null && req['patient_lng'] != null) {
          position = LatLng(
            double.parse('${req['patient_lat']}'),
            double.parse('${req['patient_lng']}'),
          );
        }
        if (req['service_title'] != null) {
          final sId = '${req['service_id']}';
          service = services.firstWhere(
            (s) => s.id == sId,
            orElse: () => ServiceItem(
              sId,
              '${req['service_title']}',
              'خدمة تمريضية',
              'خدمة تمريضية معتمدة',
              (num.tryParse('${req['price_amount']}') ?? 0).round(),
              0,
              requiresPrescription: req['requires_prescription'] == true,
            ),
          );
        }
        accuracy = 0;
        route = null;
        bill = null;
        final lat = num.tryParse('${req['nurse_lat']}');
        final lng = num.tryParse('${req['nurse_lng']}');
        nursePos = (lat != null && lng != null) ? LatLng(lat.toDouble(), lng.toDouble()) : null;

        bookingMode = req['booking_mode']?.toString() ?? 'INSTANT';
        marketplaceStatus = req['marketplace_status']?.toString();
        activeProposalsCount = (num.tryParse('${req['active_proposals_count']}') ?? 0).toInt();
        openExpiresAt = DateTime.tryParse('${req['open_expires_at']}')?.toLocal();

        stage = switch (status) {
          'SCHEDULED' => VisitStage.scheduled,
          'REQUESTED' || 'OFFERING' => (marketplaceStatus == 'OPEN_FOR_PROPOSALS' || bookingMode == 'OPEN')
              ? VisitStage.openMarketplace
              : VisitStage.searching,
          'ASSIGNED' => VisitStage.assigned,
          'EN_ROUTE' => VisitStage.enRoute,
          'ARRIVED' => VisitStage.arrived,
          'IN_SERVICE' => VisitStage.inService,
          'COMPLETED' => VisitStage.completed,
          'UNFULFILLED' || 'AWAITING_RECOVERY_CHOICE' => VisitStage.unfulfilled,
          _ => VisitStage.none,
        };

        if (stage != VisitStage.none) {
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
          if (stage == VisitStage.enRoute && nursePos != null) {
            _loadRoute();
          }
          if (stage == VisitStage.completed) {
            loadBill();
          }
        }
      } else {
        if (stage != VisitStage.none) {
          stage = VisitStage.none;
          requestId = null;
          _timer?.cancel();
        }
      }
      notifyListeners();
    } catch (_) {
      // transient network error; keep state
    }
  }

  /// Loads the signed-in patient dashboard and restores their active request.
  Future<void> loadAll() async {
    if (kDemoMode) return;
    error = null;
    await Future.wait([
      loadHistory(),
      loadServices(),
      loadBeneficiary(),
      loadReferral(),
      loadConsent(),
      restoreActiveRequest(),
    ]);
  }

  Future<void> resync() async {
    if (kDemoMode) return;
    await Future.wait([
      if (requestId == null) restoreActiveRequest() else _poll(),
      loadHistory(),
    ]);
  }

  void _startDemoMove() {
    final dest = position ?? kDamascus;
    var k = 0;
    _demoMove?.cancel();
    _demoMove = Timer.periodic(const Duration(seconds: 1), (t) {
      k++;
      final f = (1 - k / 4).clamp(0.0, 1.0);
      nursePos = LatLng(dest.latitude + 0.012 * f, dest.longitude - 0.012 * f);
      notifyListeners();
      if (k >= 4) t.cancel();
    });
  }

  VisitStage? _lastLogged;
  void _logStage() {
    if (_lastLogged == stage) return;
    _lastLogged = stage;
    switch (stage) {
      case VisitStage.enRoute:
        Analytics.log('nurse_assigned', {
          'seconds_to_assign': _searchStart == null
              ? 0
              : DateTime.now().difference(_searchStart!).inSeconds,
        });
      case VisitStage.completed:
        Analytics.log('visit_completed', {'service_id': service?.id ?? ''});
      default:
    }
  }

  Future<void> _loadRoute() async {
    final id = requestId;
    if (id == null) return;
    RouteInfo? next;
    try {
      next = RouteInfo.fromJson(await api.getMap('/v1/requests/$id/route'));
    } catch (_) {
      // ETA is optional; the map can still show recent positions.
    }
    if (requestId != id || stage != VisitStage.enRoute || nursePos == null) return;
    route = next;
    notifyListeners();
  }

  Future<String?>? _trackingFetch;
  String? _trackingId;

  Future<String?> _poll() async {
    final id = requestId;
    if (id == null) return null;
    if (_trackingId == id && _trackingFetch != null) return _trackingFetch!;
    final fetch = _fetchTracking(id);
    _trackingId = id;
    _trackingFetch = fetch;
    try {
      return await fetch;
    } finally {
      if (identical(_trackingFetch, fetch)) {
        _trackingFetch = null;
        _trackingId = null;
      }
    }
  }

  Future<String?> _fetchTracking(String id) async {
    try {
      final d = await api.getMap('/v1/requests/$id/tracking');
      if (requestId == id) clinicalApprovalStatus = d['clinical_approval_status'] as String?;
      if (id != requestId) return null;
      final status = '${d['status']}';
      bookingMode = d['booking_mode']?.toString() ?? bookingMode;
      marketplaceStatus = d['marketplace_status']?.toString();
      activeProposalsCount = (num.tryParse('${d['active_proposals_count']}') ?? 0).toInt();
      openExpiresAt = DateTime.tryParse('${d['open_expires_at']}')?.toLocal();

      stage = switch (status) {
        'SCHEDULED' => VisitStage.scheduled,
        'ASSIGNED' => VisitStage.assigned,
        'EN_ROUTE' => VisitStage.enRoute,
        'ARRIVED' => VisitStage.arrived,
        'IN_SERVICE' => VisitStage.inService,
        'COMPLETED' => VisitStage.completed,
        'UNFULFILLED' || 'AWAITING_RECOVERY_CHOICE' => VisitStage.unfulfilled,
        'ESCALATED' => VisitStage.interrupted,
        'CANCELLED' => VisitStage.none,
        _ => (marketplaceStatus == 'OPEN_FOR_PROPOSALS' || bookingMode == 'OPEN')
            ? VisitStage.openMarketplace
            : VisitStage.searching,
      };
      if (stage == VisitStage.unfulfilled || stage == VisitStage.interrupted || stage == VisitStage.none) {
        _timer?.cancel();
      }
      final lat = num.tryParse('${d['nurse_lat']}'),
          lng = num.tryParse('${d['nurse_lng']}');
      nurseBadge = d['nurseBadge'] is Map
          ? Map<String, dynamic>.from(d['nurseBadge'] as Map)
          : null;
      nursePos = (lat != null && lng != null)
          ? LatLng(lat.toDouble(), lng.toDouble())
          : null;
      if (stage == VisitStage.enRoute && nursePos != null && _pollCount++ % 3 == 0) {
        await _loadRoute();
      }
      if (id != requestId) return null;
      if (stage != VisitStage.enRoute || nursePos == null) route = null;
      _logStage();
      if (stage == VisitStage.completed) {
        await loadBill();
        if (bill?.status == 'PAID') _timer?.cancel();
      }
      notifyListeners();
      return status;
    } catch (_) {
      return null;
    }
  }

  void resetToHome() {
    _timer?.cancel();
    _demoMove?.cancel();
    stage = VisitStage.none;
    requestId = null;
    scheduledAt = null;
    route = null;
    nursePos = null;
    bill = null;
    bookingMode = 'INSTANT';
    marketplaceStatus = null;
    activeProposalsCount = 0;
    openExpiresAt = null;
    tab = 0;
    notifyListeners();
  }

  // =========================================================================
  // Smart Booking & Open Marketplace Methods
  // =========================================================================

  Future<bool> switchToOpenMarketplace({int durationMinutes = 60}) async {
    final id = requestId;
    if (id == null) return false;
    busy = true;
    notifyListeners();
    try {
      final res = await api.switchRequestToOpenMarketplace(id, durationMinutes: durationMinutes);
      bookingMode = 'OPEN';
      marketplaceStatus = 'OPEN_FOR_PROPOSALS';
      openExpiresAt = DateTime.tryParse('${res['open_expires_at']}')?.toLocal();
      stage = VisitStage.openMarketplace;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
      return true;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحويل الطلب إلى السوق المفتوح');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> retryInstantDispatch() async {
    final id = requestId;
    if (id == null) return false;
    busy = true;
    notifyListeners();
    try {
      await api.retryInstantDispatch(id);
      bookingMode = 'INSTANT';
      marketplaceStatus = null;
      stage = VisitStage.searching;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
      return true;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر إعادة محاولة البحث الفوري');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> extendWaitWindow({int additionalMinutes = 60}) async {
    final id = requestId;
    if (id == null) return false;
    try {
      final res = await api.extendWaitWindow(id, additionalMinutes: additionalMinutes);
      openExpiresAt = DateTime.tryParse('${res['open_expires_at']}')?.toLocal();
      notifyListeners();
      return true;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تمديد فترة الانتظار');
      return false;
    }
  }

  Future<List<dynamic>> loadProposals() async {
    final id = requestId;
    if (id == null) return [];
    try {
      final res = await api.getRequestProposals(id);
      activeProposalsCount = res.where((p) => p['status'] == 'PENDING').length;
      notifyListeners();
      return res;
    } catch (_) {
      return [];
    }
  }

  Future<bool> acceptProposal(String proposalId) async {
    final reqId = requestId;
    if (reqId == null) return false;
    busy = true;
    notifyListeners();
    try {
      await api.acceptProposal(reqId, proposalId);
      stage = VisitStage.assigned;
      marketplaceStatus = 'COMPLETED';
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
      await _poll();
      return true;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر قبول العرض. قد يكون العرض ملغى أو تم قبوله مسبقاً.');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> declineProposal(String proposalId, {String? reason}) async {
    final reqId = requestId;
    if (reqId == null) return false;
    try {
      await api.declineProposal(reqId, proposalId, reason: reason);
      await loadProposals();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> retryRequest() async {
    _timer?.cancel();
    _demoMove?.cancel();
    _idemKey = null;
    requestId = null;
    stage = VisitStage.searching;
    notifyListeners();
    await submit();
  }

  (String, String, int?, bool)? _lastCancellation;
  String? _cancellationKey;

  Future<Map<String, dynamic>?> loadCancellationPolicy() async {
    if (busy) return null;
    error = null;
    if (kDemoMode) return {'canCancel': true, 'requiresAcknowledgement': false};
    final id = requestId;
    if (id == null) return null;
    busy = true;
    notifyListeners();
    try {
      final result = await api.getMap('/v1/requests/$id/cancellation-policy');
      return id == requestId ? result : null;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر التحقق من حالة الزيارة قبل الإلغاء.');
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> cancel({
    String? reasonCode,
    int? expectedVersion,
    bool policyAcknowledged = false,
  }) async {
    if (busy) return false;
    if (requestId == null || stage == VisitStage.unfulfilled) {
      resetToHome();
      return true;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode) {
        final id = requestId!;
        if (reasonCode == null) return false;
        final attempt = (id, reasonCode, expectedVersion, policyAcknowledged);
        if (_lastCancellation != attempt) {
          _lastCancellation = attempt;
          _cancellationKey = const Uuid().v4();
        }
        await api.post('/v1/requests/$id/cancel', {
          'reasonCode': reasonCode,
          'idempotencyKey': _cancellationKey,
          'expectedVersion': ?expectedVersion,
          'policyAcknowledged': policyAcknowledged,
        });
      }
      _lastCancellation = null;
      _cancellationKey = null;
      resetToHome();
      return true;
    } catch (e) {
      if (await _poll() == 'CANCELLED') {
        resetToHome();
        return true;
      }
      error = explainError(e, fallback: 'تعذر تأكيد إلغاء الطلب. تحقق من حالته وحاول مجددًا.');
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void finishPayment() {
    final price = service?.price ?? 0;
    Analytics.purchase(
      id: requestId ?? 'demo',
      value: price,
      method: payMethod,
      serviceId: service?.id,
    );
    history = [
      HistoryItem(service?.title ?? 'زيارة', 'اليوم', price, 'مكتملة'),
      ...history,
    ];
    if (payMethod == 'wallet') {
      balance -= price;
      txs = [WalletTx('دفع زيارة', 'اليوم • مكتملة', -price), ...txs];
    }
  }

  void reset() {
    _timer?.cancel();
    _demoMove?.cancel();
    nursePos = null;
    route = null;
    bill = null;
    promo = null;
    promoCode = '';
    promoMsg = null;
    stage = VisitStage.none;
    requestId = null;
    service = null;
    selectedServiceQuantities.clear();
    clinicalApprovalStatus = null;
    tab = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
