import 'dart:async';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'alarm.dart';
import 'availability_manager.dart';

enum NurseStage { idle, offer, enRoute, arrived, inService, completed }

class Offer {
  final String id, service, area;
  final double km;
  final int price, nurseShare;
  final DateTime expiresAt;
  Offer(
    this.id,
    this.service,
    this.area,
    this.km,
    this.price,
    this.nurseShare,
    this.expiresAt,
  );
}

class VisitRecord {
  final String title, date;
  final int share;
  const VisitRecord(this.title, this.date, this.share);
}

/// Nurse app state. Uses AvailabilityManager for all readiness, telemetry, and background sync.
class NurseController extends ChangeNotifier {
  final TamreedyApi api = TamreedyApi();
  late final AvailabilityManager availabilityManager;

  int tab = 0;
  NurseStage stage = NurseStage.idle;
  Offer? offer;
  String? assignmentId;
  bool busy = false;
  String? error;

  bool get available => availabilityManager.intentAvailable;
  NurseReadinessState get readinessState => availabilityManager.state;

  // Bill + cash collection after the visit is closed.
  String? requestId;
  BillInfo? bill;
  String? collectMsg;
  bool collectShort = false;

  // Profile and verified clinical skills
  List<String> skills = [];
  bool verified = false;

  // What the nurse owes the company (or is owed) from cash collected: `/v1/nurse/me/dues`.
  Map<String, dynamic> dues = {
    'balance': 3400,
    'limit': 10000,
    'blocked': false,
    'history': [],
  };

  Future<void> loadDues() async {
    if (kDemoMode) return;
    try {
      dues = await api.getMap('/v1/nurse/me/dues');
      notifyListeners();
    } catch (_) {
      /* shown as last known */
    }
  }

  // Live navigation state (N03).
  LatLng? myPos;
  LatLng? dest;
  String patientAddress = '';
  String serviceTitle = 'زيارة تمريضية';
  RouteInfo? route;
  StreamSubscription<Position>? _posSub;
  Timer? _routeTimer, _demoMove;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Home / earnings (demo values mirror the approved designs).
  int todayRequests = 5, completedVisits = 4;
  int netDue = 28450, commission = 7200, monthVisits = 26;
  List<VisitRecord> history = const [
    VisitRecord('زيارة تمريضية', '20 نوفمبر 2026 • المزة', 960),
    VisitRecord('علامات حيوية', '19 نوفمبر 2026 • دمر', 720),
    VisitRecord('متابعة منزلية', '18 نوفمبر 2026 • كفرسوسة', 1800),
  ];
  final String lastPaymentMethod = 'نقدية';

  NurseController() {
    availabilityManager = AvailabilityManager(
      api: api,
      onOffersReceived: (list) async {
        if (list.isNotEmpty && stage == NurseStage.idle) {
          _showOffer(Map<String, dynamic>.from(list.first as Map));
        }
      },
    );
    availabilityManager.addListener(notifyListeners);
    OfferAlarm.onTap = resync;
    if (!kDemoMode) loadLive();
  }

  /// Replaces demo figures with server values (summary + earnings) and restores active state.
  Future<void> loadLive() async {
    try {
      await restoreActiveAssignment();
      final s = await api.getMap('/v1/nurse/me/summary');
      todayRequests = (s['requests_today'] as num?)?.toInt() ?? 0;
      completedVisits = (s['completed_today'] as num?)?.toInt() ?? 0;
      await loadDues();
      await loadProfile();
      final e = await api.getMap('/v1/nurse/me/earnings');
      final m = Map<String, dynamic>.from(e['month'] as Map);
      monthVisits = (m['visits'] as num?)?.toInt() ?? 0;
      netDue = (num.tryParse('${m['net_due']}') ?? 0).round();
      commission = (num.tryParse('${m['commission']}') ?? 0).round();
      history = [
        for (final r in (e['recent'] as List))
          VisitRecord(
            '${(r as Map)['title']}',
            '${r['completed_at']}'.split('T').first,
            (num.tryParse('${r['nurse_share']}') ?? 0).round(),
          ),
      ];
      notifyListeners();
    } catch (_) {
      error = 'تعذر تحميل ملخص الأرباح من الخادم';
      notifyListeners();
    }
  }

  /// Restores active assignment and true server status on app launch or reconnect.
  Future<void> restoreActiveAssignment() async {
    if (kDemoMode) return;
    try {
      final res = await api.getMap('/v1/nurse/me/active-assignment');
      final isAvail = res['availability'] == 'AVAILABLE';
      if (res['hasActive'] == true && res['assignment'] != null) {
        availabilityManager.setActiveAssignment(true);
        final asgn = Map<String, dynamic>.from(res['assignment'] as Map);
        assignmentId = asgn['assignment_id']?.toString();
        requestId = asgn['request_id']?.toString();
        final reqStatus = '${asgn['request_status']}';
        if (asgn['service_title'] != null) {
          serviceTitle = '${asgn['service_title']}';
        }
        if (asgn['address_text'] != null) {
          patientAddress = '${asgn['address_text']}';
        }
        if (asgn['patient_lat'] != null && asgn['patient_lng'] != null) {
          dest = LatLng(
            double.parse('${asgn['patient_lat']}'),
            double.parse('${asgn['patient_lng']}'),
          );
        }

        switch (reqStatus) {
          case 'ASSIGNED':
          case 'EN_ROUTE':
            stage = NurseStage.enRoute;
            _startNavigation();
            break;
          case 'ARRIVED':
            stage = NurseStage.arrived;
            break;
          case 'IN_SERVICE':
            stage = NurseStage.inService;
            break;
          case 'COMPLETED':
            stage = NurseStage.completed;
            loadBill();
            break;
          default:
            stage = NurseStage.idle;
            assignmentId = null;
            requestId = null;
        }
      } else {
        availabilityManager.setActiveAssignment(false);
        if (stage != NurseStage.idle && stage != NurseStage.offer) {
          stage = NurseStage.idle;
          assignmentId = null;
          requestId = null;
          _stopNavigation();
        }
      }
      if (isAvail && !availabilityManager.intentAvailable && stage == NurseStage.idle) {
        await availabilityManager.setAvailability(true);
      }
      notifyListeners();
    } catch (_) {
      // transient network error; keep state
    }
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
    if (!kDemoMode && (i == 0 || i == 2)) loadLive();
  }

  Future<void> setAvailable(bool v) async {
    if (stage != NurseStage.idle) return;
    Analytics.log('availability_changed', {'available': v ? 1 : 0});
    if (v) {
      OfferAlarm.requestPermissions().catchError((_) {});
    }
    error = null;
    notifyListeners();

    if (kDemoMode) {
      await availabilityManager.setAvailability(v);
      if (v) {
        Timer(const Duration(seconds: 4), () {
          if (stage == NurseStage.idle) {
            _showOffer({
              'id': 'demo-offer',
              'title_ar': 'تغيير ضماد',
              'area': 'المزة - دمشق',
              'distance_m': 2400,
              'price_amount': 1200,
              'commission_bps': 2000,
              'expires_at': DateTime.now().add(const Duration(seconds: 30)).toIso8601String(),
            });
          }
        });
      }
      return;
    }

    try {
      await availabilityManager.setAvailability(v);
    } on DioException catch (e) {
      error = explainError(e, fallback: 'تعذر تغيير الحالة؛ تحقق من الحساب والترخيص');
      notifyListeners();
    } catch (e) {
      error = 'تعذر تغيير الحالة؛ يرجى التأكد من تشغيل أذونات الموقع والاتصال';
      notifyListeners();
    }
  }

  /// Reconcile with the server after a reconnect, app resume or push.
  Future<void> resync() async {
    if (kDemoMode) return;
    await loadLive();
    if (available && stage == NurseStage.idle) {
      await availabilityManager.syncNow();
    }
  }

  /// Realtime event handler from WebSocket / Socket.io
  void onLive(String type) {
    if (type == 'offer.created') {
      _fetchOffers();
    } else if (type == 'offer.expired') {
      if (stage == NurseStage.offer) {
        decline(expired: true);
      }
    } else if (type == 'request.cancelled') {
      if (stage == NurseStage.offer) {
        decline(expired: true);
      } else {
        restoreActiveAssignment();
      }
    } else if (type == 'catalog.changed') {
      loadLive();
    } else {
      resync();
    }
  }

  Future<void> _fetchOffers() async {
    if (kDemoMode || stage != NurseStage.idle) return;
    try {
      final list = await api.getList('/v1/nurse/me/offers');
      if (list.isNotEmpty) {
        _showOffer(Map<String, dynamic>.from(list.first as Map));
      }
    } catch (_) {
      /* next resync will retry */
    }
  }

  Future<void> loadProfile() async {
    if (kDemoMode) {
      skills = ['حقن وعلاجات وريدية', 'تضميد الجروح', 'قياس العلامات الحيوية'];
      verified = true;
      notifyListeners();
      return;
    }
    try {
      final p = await api.getMap('/v1/nurse/me/profile');
      verified = p['verified'] == true;
      if (p['skills'] is List) {
        skills = (p['skills'] as List)
            .map((s) => (s['title_ar'] ?? '').toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      notifyListeners();
    } catch (_) {}
  }

  void _showOffer(Map<String, dynamic> o) {
    final title = (o['title_ar'] ?? 'زيارة تمريضية').toString();
    final area = (o['area'] ?? '—').toString();
    patientAddress = area;
    serviceTitle = title;
    final exp = DateTime.tryParse('${o['expires_at']}') ??
        DateTime.now().add(const Duration(seconds: 30));
    final netShare = ((num.tryParse('${o['price_amount'] ?? 0}') ?? 0) *
            (10000 -
                (num.tryParse('${o['commission_bps'] ?? 2000}') ?? 2000)) /
            10000)
        .round();
    offer = Offer(
      o['id'].toString(),
      title,
      area,
      (num.tryParse('${o['distance_m'] ?? 0}') ?? 0) / 1000,
      (num.tryParse('${o['price_amount'] ?? 0}') ?? 0).round(),
      netShare,
      exp,
    );
    stage = NurseStage.offer;
    tab = 1;
    Analytics.log('offer_received');

    // Trigger insistent alert and alarm immediately
    final ttl = exp.difference(DateTime.now()).inSeconds.clamp(5, 60);
    OfferAlarm.show(AlarmData(
      offer!.id,
      'طلب جديد في $area',
      '$title — حصتك $netShare ل.س',
      ttl,
    )).catchError((_) {});

    notifyListeners();
  }



  Future<void> accept() async {
    OfferAlarm.cancelAll(); // silence the alarm as soon as she acts
    if (offer == null || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode) {
        final a = await api.post('/v1/nurse/offers/${offer!.id}/accept');
        assignmentId = a['assignmentId']?.toString();
        requestId = a['requestId']?.toString();
        if (assignmentId == null || assignmentId!.isEmpty) {
          throw Exception('لم يتم استلام معرف الإسناد');
        }
        // Transitions status ASSIGNED -> EN_ROUTE on the backend
        await api.post('/v1/nurse/assignments/$assignmentId/depart');
      }
      availabilityManager.setActiveAssignment(true);
      stage = NurseStage.enRoute;
      Analytics.log('offer_accepted');
      await _startNavigation();
    } catch (e) {
      error = explainError(e, fallback: 'لم يعد العرض متاحًا أو حصل عليه ممرض آخر');
      if (assignmentId != null) {
        await restoreActiveAssignment();
      } else {
        stage = NurseStage.idle;
        offer = null;
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> decline({bool expired = false}) async {
    OfferAlarm.cancelAll();
    Analytics.log(expired ? 'offer_expired' : 'offer_declined');
    if (!kDemoMode && offer != null) {
      try {
        await api.post('/v1/nurse/offers/${offer!.id}/decline');
      } catch (_) {}
    }
    offer = null;
    stage = NurseStage.idle;
    tab = 0;
    notifyListeners();
  }

  Future<void> _step(String command, NurseStage next) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (!kDemoMode && assignmentId != null) {
        await api.post('/v1/nurse/assignments/$assignmentId/$command');
      }
      stage = next;
    } on DioException catch (de) {
      if (de.response?.statusCode == 409) {
        // Resync true state on 409 conflict
        await restoreActiveAssignment();
      } else {
        error = explainError(de, fallback: 'تعذر تأكيد الانتقال. راجع حالة الطلب قبل إعادة المحاولة.');
      }
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تأكيد الانتقال. راجع حالة الطلب قبل إعادة المحاولة.');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> arrive() async {
    if (stage != NurseStage.enRoute) return;
    await _step('arrive', NurseStage.arrived);
    if (stage == NurseStage.arrived) {
      _stopNavigation();
    }
  }

  Future<void> start() async {
    if (stage != NurseStage.arrived) return;
    await _step('start', NurseStage.inService);
    Analytics.log('visit_started');
  }

  Future<void> complete() async {
    if (stage != NurseStage.inService) return;
    await _step('complete', NurseStage.completed);
    Analytics.log('visit_completed', {'service_id': offer?.service ?? ''});
    if (stage == NurseStage.completed) await loadBill();
    if (stage == NurseStage.completed && offer != null) {
      history = [
        VisitRecord(
          offer!.service,
          'اليوم • ${offer!.area.split(' ').first}',
          offer!.nurseShare,
        ),
        ...history,
      ];
      completedVisits++;
      monthVisits++;
    }
  }

  /// Starts GPS streaming + route refresh while driving to the patient.
  Future<void> _startNavigation() async {
    if (kDemoMode) {
      dest = kDamascus;
      patientAddress = 'دمشق - المزة • جانب حديقة الجلاء';
      var k = 0;
      _demoMove?.cancel();
      _demoMove = Timer.periodic(const Duration(seconds: 1), (t) {
        k++;
        final f = (1 - k / 8).clamp(0.0, 1.0);
        myPos = LatLng(dest!.latitude + 0.012 * f, dest!.longitude - 0.012 * f);
        notifyListeners();
        if (k >= 8) t.cancel();
      });
      return;
    }
    try {
      final d = await api.getMap('/v1/nurse/assignments/$assignmentId');
      dest = LatLng(
        double.parse('${d['latitude']}'),
        double.parse('${d['longitude']}'),
      );
      if (d['address_text'] != null && '${d['address_text']}'.trim().isNotEmpty) {
        patientAddress = '${d['address_text']}'.trim();
      }
      if (d['service_title'] != null && '${d['service_title']}'.trim().isNotEmpty) {
        serviceTitle = '${d['service_title']}'.trim();
      }
      notifyListeners();
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        return;
      }
      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationTitle: 'تمريضي',
                notificationText: 'مشاركة موقعك مع المريض أثناء التوجه للزيارة',
                enableWakeLock: true,
              ),
            )
          : const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            );
      _posSub = Geolocator.getPositionStream(locationSettings: settings).listen((
        pos,
      ) {
        myPos = LatLng(pos.latitude, pos.longitude);
        notifyListeners();
        // The server accepts location only while available/assigned; throttle uploads.
        if (DateTime.now().difference(_lastSent).inSeconds >= 4) {
          _lastSent = DateTime.now();
          api
              .put('/v1/nurse/me/location', {
                'latitude': pos.latitude,
                'longitude': pos.longitude,
                'accuracyMeters': pos.accuracy,
              })
              .catchError((_) => <String, dynamic>{});
        }
      });
      await _loadRoute();
      _routeTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _loadRoute(),
      );
    } catch (_) {
      error = 'تعذر بدء التتبع؛ تحقق من أذونات الموقع';
    }
  }

  Future<void> _loadRoute() async {
    try {
      route = RouteInfo.fromJson(
        await api.getMap('/v1/nurse/assignments/$assignmentId/route'),
      );
      notifyListeners();
    } catch (_) {
      route = null;
    }
  }

  void _stopNavigation() {
    _posSub?.cancel();
    _routeTimer?.cancel();
    _demoMove?.cancel();
    _posSub = null;
    route = null;
    notifyListeners();
  }

  /// Bill computed by the server from the time at the patient (demo: 47 minutes at the offered price).
  Future<void> loadBill() async {
    if (kDemoMode) {
      final o = offer;
      final b = finalBill(
        PricingRule(
          basePrice: o?.price ?? 1200,
          includedMinutes: 30,
          blockMinutes: 15,
          blockPrice: 400,
          roundingStep: 50,
        ),
        47 * 60,
      );
      bill = BillInfo(
        due: b.due,
        minutes: b.minutes,
        gross: b.gross,
        discount: b.discount,
        collected: 0,
        remaining: b.due,
        status: 'DUE',
        nurseEarning: (b.gross * 0.8).round(),
      );
    } else if (requestId != null) {
      try {
        bill = BillInfo.fromJson(
          await api.getMap('/v1/nurse/requests/$requestId/bill'),
        );
      } catch (_) {
        error = 'تعذر تحميل الفاتورة';
      }
    }
    notifyListeners();
  }

  /// Record cash received. A short amount keeps the bill open and says how much is still missing.
  Future<void> collect(int amount) async {
    final b = bill;
    if (b == null || amount <= 0 || busy) return;
    busy = true;
    notifyListeners();
    try {
      if (kDemoMode) {
        final r = applyCollection(b.payable, b.collected, amount);
        collectMsg = r.message;
        collectShort = !r.paid;
        bill = BillInfo(
          due: b.due,
          minutes: b.minutes,
          gross: b.gross,
          discount: b.discount,
          collected: r.collected,
          remaining: r.remaining,
          status: r.paid ? 'PAID' : 'PARTIAL',
          tip: b.tip,
          nurseEarning: b.nurseEarning,
          surcharge: b.surcharge,
          distanceFee: b.distanceFee,
          tax: b.tax,
          taxLabel: b.taxLabel,
        );
      } else {
        final r = await api.post('/v1/nurse/requests/$requestId/collect', {
          'amount': amount,
        });
        collectMsg = '${r['message']}';
        collectShort = r['status'] != 'PAID';
        await loadBill();
        if (!collectShort) await loadDues();
      }
      Analytics.log('cash_collected', {'paid': collectShort ? 0 : 1});
    } on DioException catch (e) {
      collectMsg = ((e.response?.data as Map?)?['code'] == 'ALREADY_PAID')
          ? 'تم الدفع مسبقًا'
          : 'تعذر تسجيل المبلغ، حاول مجددًا';
      collectShort = true;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Rate the patient (stars) + private report; real mode sends it to the server.
  Future<void> submitReport(
    int stars,
    String note, {
    String category = 'NORMAL',
  }) async {
    Analytics.log('patient_rated', {'stars': stars});
    final visit = bill?.visitId;
    if (kDemoMode || visit == null) return;
    try {
      await api.post('/v1/visits/$visit/nurse-report', {
        'category': category,
        'stars': stars,
        if (note.isNotEmpty) 'note': note,
      });
    } catch (_) {
      /* 48h window; retry from history later */
    }
  }

  void backToAvailable() {
    bill = null;
    collectMsg = null;
    collectShort = false;
    requestId = null;
    _stopNavigation();
    myPos = null;
    dest = null;
    offer = null;
    assignmentId = null;
    stage = NurseStage.idle;
    tab = 0;
    availabilityManager.setActiveAssignment(false);
    if (available) availabilityManager.syncNow();
    notifyListeners();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _routeTimer?.cancel();
    _demoMove?.cancel();
    availabilityManager.dispose();
    super.dispose();
  }
}
