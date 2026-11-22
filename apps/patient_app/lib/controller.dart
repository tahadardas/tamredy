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
  const HistoryItem(this.title, this.date, this.price, this.status);
}

class WalletTx {
  final String title, sub;
  final int amount;
  const WalletTx(this.title, this.sub, this.amount);
}

enum VisitStage { none, searching, enRoute, arrived, inService, completed, unfulfilled }

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
  String beneficiary = kDemoMode ? 'والدي - أحمد' : '';
  String address = 'دمشق - المزة';
  String extraAddress = '';
  String areaLabel = ''; // area the patient picked by name (e.g. «المزة، دمشق»)
  String notes = '';
  LatLng? position; // confirmed visit location
  double accuracy = 30;
  LatLng? nursePos;
  RouteInfo? route;
  int _pollCount = 0;
  Timer? _demoMove;
  DateTime? _searchStart;
  String payMethod = 'wallet'; // wallet | cash | mixed
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
  String? _idemKey;
  Timer? _timer;
  bool busy = false;
  String? error;

  ServiceLoadState serviceState = kDemoMode ? ServiceLoadState.loaded : ServiceLoadState.initial;
  String? serviceError;

  PatientController() {
    if (!kDemoMode) {
      loadHistory();
      loadServices();
      loadBeneficiary();
      loadReferral();
      loadConsent();
    }
  }

  /// The visit is for the patient's own beneficiary (created at sign-up), never a sample name.
  Future<void> loadBeneficiary() async {
    try {
      final b = await api.getList('/v1/beneficiaries/mine');
      if (b.isNotEmpty) {
        beneficiary = '${(b.first as Map)['display_name']}';
        notifyListeners();
      }
    } catch (_) {/* keep default */}
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
  Future<void> loadBill() async {
    if (requestId == null) return;
    if (kDemoMode) {
      bill ??= _demoBill();
    } else {
      try {
        bill = BillInfo.fromJson(
          await api.getMap('/v1/requests/$requestId/bill'),
        );
      } catch (_) {
        /* retried on the next poll/event */
      }
    }
    notifyListeners();
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
        await api.post('/v1/requests/$requestId/tip', {'amount': amount});
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
    if (kDemoMode)
      return code == 'TMDEMO12'
          ? 'تم! خصم 15% على طلبك الأول'
          : 'الكود غير صحيح';
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
          ),
      ];
      notifyListeners();
    } catch (_) {
      error = 'تعذر تحميل السجل من الخادم';
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
    quoteInfo = {};
    promo = null;
    promoCode = '';
    promoMsg = null;
    _recalc();
    if (!kDemoMode) _quote();
    Analytics.log('service_selected', {'service_id': s.id});
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
  Future<void> useCurrentLocation() async {
    error = null;
    if (kDemoMode) {
      position = kDamascus;
      address = 'دمشق - المزة';
      notifyListeners();
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
      position = LatLng(fix.latitude, fix.longitude);
      accuracy = fix.accuracy;
      error = null;
    } catch (_) {
      error = 'تعذر تحديد موقعك الحالي. تأكد من تفعيل الـ GPS أو اختر منطقتك من القائمة.';
    }
    notifyListeners();
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  void setPicked(LatLng point, String addr) {
    position = point;
    if (addr.isNotEmpty) address = addr;
    notifyListeners();
  }

  /// Creates the request, then follows its lifecycle.
  Future<bool> submit() async {
    if (service == null) return false;
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
    if (position == null) {
      busy = false;
      error = 'يلزم تأكيد الموقع قبل الإرسال';
      notifyListeners();
      return false;
    }
    try {
      _idemKey ??= const Uuid().v4();
      final benef = await api.getList('/v1/beneficiaries/mine');
      final r = await api.post(
        '/v1/requests',
        {
          'beneficiaryId': (benef.first as Map)['id'],
          'serviceId': service!.id,
          'latitude': position!.latitude,
          'longitude': position!.longitude,
          'accuracyMeters': accuracy.round(),
          'locationSource': 'MANUAL_PIN',
          'addressText': '${areaLabel.isNotEmpty ? areaLabel : address} $extraAddress'.trim(),
          'nonEmergencyConfirmed': true,
          if (service!.requiresPrescription) 'prescriptionConfirmed': true,
          if (promoCode.isNotEmpty) 'promoCode': promoCode,
        },
        {'Idempotency-Key': _idemKey!},
      );
      requestId = r['id'] as String?;
      _idemKey = null;
      stage = VisitStage.searching;
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
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/me/active-request');
      if (res['hasActive'] == true && res['request'] != null) {
        final req = Map<String, dynamic>.from(res['request'] as Map);
        requestId = req['id']?.toString();
        final status = '${req['status']}';
        if (req['address_text'] != null) {
          address = '${req['address_text']}';
        }
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
        final lat = num.tryParse('${req['nurse_lat']}');
        final lng = num.tryParse('${req['nurse_lng']}');
        nursePos = (lat != null && lng != null) ? LatLng(lat.toDouble(), lng.toDouble()) : null;

        stage = switch (status) {
          'REQUESTED' || 'OFFERING' => VisitStage.searching,
          'ASSIGNED' || 'EN_ROUTE' => VisitStage.enRoute,
          'ARRIVED' => VisitStage.arrived,
          'IN_SERVICE' => VisitStage.inService,
          'COMPLETED' => VisitStage.completed,
          _ => VisitStage.none,
        };

        if (stage != VisitStage.none) {
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 6), (_) => _poll());
          if (stage == VisitStage.enRoute) {
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

  /// Reconcile with the server after a reconnect, app resume or push.
  /// Everything the signed-in user sees. Called right after login (the data requested at app start had no token).
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
    await _poll();
    await loadHistory();
    await loadServices();
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
    try {
      route = RouteInfo.fromJson(
        await api.getMap('/v1/requests/$requestId/route'),
      );
    } catch (_) {
      route = null; // ETA is optional: map still shows both pins
    }
  }

  Future<void> _poll() async {
    if (requestId == null) return;
    try {
      final d = await api.getMap('/v1/requests/$requestId/tracking');
      final status = '${d['status']}';
      stage = switch (status) {
        'EN_ROUTE' => VisitStage.enRoute,
        'ARRIVED' => VisitStage.arrived,
        'IN_SERVICE' => VisitStage.inService,
        'COMPLETED' => VisitStage.completed,
        'UNFULFILLED' => VisitStage.unfulfilled,
        'CANCELLED' => VisitStage.none,
        _ => VisitStage.searching,
      };
      if (stage == VisitStage.unfulfilled || stage == VisitStage.none) {
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
      if (stage == VisitStage.enRoute && _pollCount++ % 3 == 0)
        await _loadRoute();
      if (stage != VisitStage.enRoute) route = null;
      _logStage();
      if (stage == VisitStage.completed) {
        await loadBill();
        if (bill?.status == 'PAID') _timer?.cancel();
      }
      notifyListeners();
    } catch (_) {
      /* keep last known state */
    }
  }

  void resetToHome() {
    _timer?.cancel();
    _demoMove?.cancel();
    stage = VisitStage.none;
    requestId = null;
    route = null;
    nursePos = null;
    bill = null;
    tab = 0;
    notifyListeners();
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

  Future<bool> cancel() async {
    if (requestId == null || stage == VisitStage.unfulfilled) {
      resetToHome();
      return true;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode) {
        await api.post('/v1/requests/$requestId/cancel');
      }
      resetToHome();
      return true;
    } catch (_) {
      // Regardless of network state or if already cancelled on server, clean up locally
      resetToHome();
      return true;
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
    tab = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
