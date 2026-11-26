import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

class PatientService {
  final String id;
  final String code;
  final String? categoryId;
  final String categoryCode;
  final String categoryTitleAr;
  final String titleAr;
  final String descriptionAr;
  final int priceAmount;
  final String currencyCode;
  final int expectedMinutes;
  final bool requiresPrescription;
  final bool requiresClinicalReview;
  final bool schedulingAllowed;
  final bool recurringAllowed;
  final bool nightAvailable;
  final List<String> requiredSkills;
  final PricingRule rule;

  const PatientService({
    required this.id,
    required this.code,
    this.categoryId,
    this.categoryCode = '',
    this.categoryTitleAr = '',
    required this.titleAr,
    required this.descriptionAr,
    required this.priceAmount,
    this.currencyCode = 'SYP_NEW',
    this.expectedMinutes = 30,
    this.requiresPrescription = false,
    this.requiresClinicalReview = false,
    this.schedulingAllowed = true,
    this.recurringAllowed = false,
    this.nightAvailable = true,
    this.requiredSkills = const [],
    this.rule = const PricingRule(basePrice: 0),
  });

  factory PatientService.fromJson(Map<String, dynamic> j) {
    final rule = PricingRule.fromService(j);
    final rawSkills = j['required_skills'];
    return PatientService(
      id: '${j['id'] ?? ''}',
      code: '${j['code'] ?? ''}'.toUpperCase(),
      categoryId: j['category_id']?.toString(),
      categoryCode: '${j['category_code'] ?? ''}',
      categoryTitleAr: '${j['category_title_ar'] ?? ''}',
      titleAr: '${j['title_ar'] ?? j['titleAr'] ?? 'خدمة تمريضية'}',
      descriptionAr: '${j['description_ar'] ?? ''}'.trim().isNotEmpty
          ? '${j['description_ar']}'.trim()
          : (j['requires_prescription'] == true
                ? 'تتطلب وصفة طبية سارية وتُنفذ عبر كادر مرخص.'
                : 'تُنفذ عبر كوادر تمريضية مرخصة وفق معايير السلامة.'),
      priceAmount: rule.basePrice,
      currencyCode: '${j['currency_code'] ?? 'SYP_NEW'}',
      expectedMinutes: (num.tryParse('${j['expected_minutes']}') ?? 30).toInt(),
      requiresPrescription: j['requires_prescription'] == true,
      requiresClinicalReview: j['requires_clinical_review'] == true,
      schedulingAllowed: j['scheduling_allowed'] != false,
      recurringAllowed: j['recurring_visits_allowed'] == true,
      nightAvailable: j['night_availability'] != false,
      requiredSkills: rawSkills is List ? rawSkills.map((e) => '$e').toList() : const [],
      rule: rule,
    );
  }
}

class CatalogEstimateResult {
  final int totalBasePrice;
  final int totalExpectedMinutes;
  final int minEstimate;
  final int expectedEstimate;
  final double surchargePercent;
  final double taxPercent;
  final String taxLabel;
  final bool requiresPrescription;
  final bool requiresClinicalReview;
  final String? promoAppliedCode;
  final int promoDiscount;

  const CatalogEstimateResult({
    required this.totalBasePrice,
    required this.totalExpectedMinutes,
    required this.minEstimate,
    required this.expectedEstimate,
    this.surchargePercent = 0,
    this.taxPercent = 0,
    this.taxLabel = 'ضريبة',
    this.requiresPrescription = false,
    this.requiresClinicalReview = false,
    this.promoAppliedCode,
    this.promoDiscount = 0,
  });

  factory CatalogEstimateResult.fromJson(Map<String, dynamic> j) {
    final est = j['estimate'] is Map
        ? Map<String, dynamic>.from(j['estimate'] as Map)
        : const <String, dynamic>{};
    return CatalogEstimateResult(
      totalBasePrice: (num.tryParse('${j['totalBasePrice'] ?? 0}') ?? 0).round(),
      totalExpectedMinutes: (num.tryParse('${j['totalExpectedMinutes'] ?? 30}') ?? 30).toInt(),
      minEstimate: (num.tryParse('${est['min'] ?? j['totalBasePrice'] ?? 0}') ?? 0).round(),
      expectedEstimate: (num.tryParse('${est['expected'] ?? j['totalBasePrice'] ?? 0}') ?? 0).round(),
      surchargePercent: (num.tryParse('${est['surchargePercent'] ?? 0}') ?? 0).toDouble(),
      taxPercent: (num.tryParse('${est['taxPercent'] ?? 0}') ?? 0).toDouble(),
      taxLabel: '${est['taxLabel'] ?? 'ضريبة'}',
      requiresPrescription: j['requiresPrescription'] == true,
      requiresClinicalReview: j['requiresClinicalReview'] == true,
      promoAppliedCode: est['promoCode']?.toString(),
      promoDiscount: (num.tryParse('${est['discount'] ?? 0}') ?? 0).round(),
    );
  }
}

const _demoCategories = <TypedCategory>[
  TypedCategory(id: 'cat-inj', code: 'INJECTIONS', titleAr: 'الحقن والأدوية', icon: 'vaccines', sortOrder: 1),
  TypedCategory(id: 'cat-wnd', code: 'WOUNDS', titleAr: 'الجروح والضمادات', icon: 'healing', sortOrder: 2),
  TypedCategory(id: 'cat-vit', code: 'VITALS', titleAr: 'المتابعة الحيوية', icon: 'monitor_heart', sortOrder: 3),
  TypedCategory(id: 'cat-eld', code: 'ELDERCARE', titleAr: 'رعاية المسنين', icon: 'elderly', sortOrder: 4),
];

const _demoServices = <PatientService>[
  PatientService(
    id: 'demo-inj-im',
    code: 'INJ_IM',
    categoryId: 'cat-inj',
    categoryCode: 'INJECTIONS',
    categoryTitleAr: 'الحقن والأدوية',
    titleAr: 'حقنة عضلية أو وريدية',
    descriptionAr: 'تُنفذ مع مراعاة التعقيم الكامل والتثبت من الوصفة الطبية.',
    priceAmount: 35000,
    expectedMinutes: 20,
    requiresPrescription: true,
    rule: PricingRule(basePrice: 35000, expectedMinutes: 20),
  ),
  PatientService(
    id: 'demo-iv-drip',
    code: 'IV_DRIP',
    categoryId: 'cat-inj',
    categoryCode: 'INJECTIONS',
    categoryTitleAr: 'الحقن والأدوية',
    titleAr: 'تركيب سيروم وريدي ومتابعته',
    descriptionAr: 'تركيب قثطرة وريدية ومراقبة معدل التسريب والعلامات الحيوية.',
    priceAmount: 65000,
    expectedMinutes: 45,
    requiresPrescription: true,
    rule: PricingRule(basePrice: 65000, expectedMinutes: 45),
  ),
  PatientService(
    id: 'demo-wound',
    code: 'WOUND_CARE',
    categoryId: 'cat-wnd',
    categoryCode: 'WOUNDS',
    categoryTitleAr: 'الجروح والضمادات',
    titleAr: 'غيار جرح جراحي معقم',
    descriptionAr: 'تنظيف وتعقيم الجرح وتبديل الضماد الطبي بأدوات معقمة.',
    priceAmount: 55000,
    expectedMinutes: 35,
    rule: PricingRule(basePrice: 55000, expectedMinutes: 35),
  ),
  PatientService(
    id: 'demo-vitals',
    code: 'VITALS_CHECK',
    categoryId: 'cat-vit',
    categoryCode: 'VITALS',
    categoryTitleAr: 'المتابعة الحيوية',
    titleAr: 'فحص العلامات الحيوية الشامل',
    descriptionAr: 'قياس ضغط الدم والنبض والحرارة والأكسجة وسكر الدم وتوثيقها.',
    priceAmount: 30000,
    expectedMinutes: 25,
    rule: PricingRule(basePrice: 30000, expectedMinutes: 25),
  ),
];

class CatalogStore extends ChangeNotifier {
  final TamreedyApi api;

  CatalogStore({required this.api});

  bool loading = false;
  String? error;
  DateTime? lastUpdatedAt;

  List<TypedCategory> categories = const [];
  List<PatientService> services = const [];
  String? selectedCategoryId;
  String searchQuery = '';

  static String _normalizeArabicSearch(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
  }

  List<PatientService> get filteredServices {
    final q = _normalizeArabicSearch(searchQuery);
    return services.where((s) {
      if (selectedCategoryId != null &&
          selectedCategoryId!.isNotEmpty &&
          s.categoryId != selectedCategoryId &&
          s.categoryCode != selectedCategoryId) {
        return false;
      }
      if (q.isEmpty) return true;
      return _normalizeArabicSearch(s.titleAr).contains(q) ||
          _normalizeArabicSearch(s.descriptionAr).contains(q) ||
          _normalizeArabicSearch(s.categoryTitleAr).contains(q);
    }).toList();
  }

  List<PatientService> get popularServices => services.take(6).toList();

  PatientService? byId(String id) {
    for (final s in services) {
      if (s.id == id) return s;
    }
    return null;
  }

  void setCategory(String? categoryId) {
    selectedCategoryId = categoryId;
    notifyListeners();
  }

  void setSearchQuery(String value) {
    searchQuery = value;
    notifyListeners();
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (loading) return;
    if (!forceRefresh && services.isNotEmpty) return;

    if (kDemoMode) {
      categories = _demoCategories;
      services = _demoServices;
      lastUpdatedAt = DateTime.now();
      error = null;
      notifyListeners();
      return;
    }

    loading = true;
    error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        api.getList('/v1/categories'),
        api.getList('/v1/services'),
      ]);
      categories = [
        for (final row in results[0])
          if (row is Map) TypedCategory.fromJson(Map<String, dynamic>.from(row)),
      ];
      services = [
        for (final row in results[1])
          if (row is Map) PatientService.fromJson(Map<String, dynamic>.from(row)),
      ];
      lastUpdatedAt = DateTime.now();
      error = null;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحميل قائمة الخدمات من الخادم');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<CatalogEstimateResult?> estimate({
    required Map<String, int> quantities,
    String? promoCode,
  }) async {
    if (quantities.isEmpty) return null;
    if (kDemoMode) {
      var base = 0;
      var mins = 0;
      var reqRx = false;
      for (final entry in quantities.entries) {
        final svc = byId(entry.key);
        if (svc == null) continue;
        base += svc.priceAmount * entry.value;
        mins += svc.expectedMinutes * entry.value;
        if (svc.requiresPrescription) reqRx = true;
      }
      return CatalogEstimateResult(
        totalBasePrice: base,
        totalExpectedMinutes: mins,
        minEstimate: base,
        expectedEstimate: base,
        requiresPrescription: reqRx,
      );
    }

    final res = await api.post('/v1/catalog/estimate', {
      'items': [
        for (final entry in quantities.entries)
          {'serviceId': entry.key, 'quantity': entry.value},
      ],
      if (promoCode != null && promoCode.trim().isNotEmpty)
        'promoCode': promoCode.trim().toUpperCase(),
    });
    return CatalogEstimateResult.fromJson(res);
  }
}
