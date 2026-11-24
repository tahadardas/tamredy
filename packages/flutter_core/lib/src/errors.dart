import 'package:dio/dio.dart';

const _codes = <String, String>{
  'LOGIN_INVALID': 'رقم الهاتف أو كلمة المرور غير صحيحة',
  'ACCOUNT_LOCKED': 'الحساب مقفل مؤقتًا بسبب محاولات خاطئة كثيرة. حاول بعد 15 دقيقة',
  'ACCOUNT_INACTIVE': 'الحساب موقوف. تواصل مع الإدارة',
  'PASSWORD_CHANGE_REQUIRED': 'يجب تغيير كلمة المرور أولًا',
  'WRONG_PASSWORD': 'كلمة المرور الحالية غير صحيحة',
  'WEAK_PASSWORD': 'كلمة المرور ضعيفة: لا تستخدم الحالية أو 123456 أو رقم هاتفك',
  'PHONE_ALREADY_REGISTERED': 'هذا الرقم مسجّل مسبقًا، جرّب تسجيل الدخول',
  'REGISTRATION_CLOSED': 'التسجيل مغلق حاليًا',
  'TOO_MANY_REGISTRATIONS': 'محاولات تسجيل كثيرة، حاول لاحقًا',
  'REGION_INVALID': 'اختر المحافظة والمنطقة من القائمة',
  'ORDERS_PAUSED': 'استقبال الطلبات متوقف مؤقتًا، نعود قريبًا',
  'FILE_TOO_LARGE': 'الملف أكبر من 8 ميغابايت',
  'FILE_TYPE_NOT_ALLOWED': 'يُسمح بملفات PDF وصور JPG أو PNG فقط',
  'FILE_REQUIRED': 'اختر ملفًا أولًا',
  'LICENSE_FIELDS_TOGETHER': 'اكتب رقم الرخصة وتاريخ انتهائها',
  'TOO_MANY_DOCUMENTS': 'بلغت الحد الأقصى من المستندات',
  'SETTLEMENT_REQUIRED': 'عليك تسوية المستحقات للشركة قبل قبول طلبات جديدة',
  'NURSE_NOT_VERIFIED': 'رخصتك لم تُعتمد بعد',
  'SCHEDULE_NIGHT_RESTRICTED': 'هذا الموعد غير متاح وفق سياسة السلامة. اختر موعدًا آخر.',
  'SCHEDULE_SAFETY_COVERAGE_NOT_PLANNED': 'لا توجد تغطية سلامة مجدولة لهذا الموعد. اختر موعدًا آخر.',
  'VISIT_SAFETY_REVIEW_REQUIRED': 'يتطلب الطلب مراجعة السلامة قبل الإسناد.',
  'VISIT_COMPANION_REQUIRED': 'تتطلب الزيارة مرافقًا مهنيًا متاحًا ومؤكدًا.',
  'VISIT_COMPANION_BUSY': 'أنت محجوز حاليًا لمرافقة زيارة.',
  'NIGHT_POLICY_RESTRICTED': 'هذا العرض غير متاح خلال فترة العمل الليلي.',
  'NIGHT_POLICY_OPT_IN_REQUIRED': 'يلزم تأكيد موافقتك على استقبال عروض العمل الليلي.',
  'NIGHT_POLICY_COVERAGE_REQUIRED': 'لا تتوفر تغطية سلامة لهذه الزيارة الآن.',
  'OFFER_EXPIRED': 'انتهت مهلة هذا العرض',
  'REQUEST_ALREADY_ASSIGNED': 'قبِل هذا الطلب ممرض آخر',
  'REQUEST_CANNOT_BE_CANCELLED': 'لا يمكن إلغاء الطلب في حالته الحالية',
  'PROMO_NOT_FOUND': 'كود الخصم غير صحيح',
  'PROMO_EXPIRED': 'كود الخصم منتهي',
  'PROMO_ALREADY_USED': 'استخدمت هذا الكود من قبل',
  'APPLICATION_ALREADY_OPEN': 'لديك طلب انضمام قيد المراجعة بهذا الرقم، سنتواصل معك',
  'LICENSE_EXPIRED': 'الوثيقة منتهية الصلاحية؛ ارفع وثيقة سارية',
  'ROLE_NOT_ALLOWED': 'هذا الحساب غير مخصص لهذا التطبيق',
};

String? nightPolicyMessage(Object? code) =>
    code is String && (code.startsWith('NIGHT_POLICY_') || code.startsWith('VISIT_COMPANION_') || code == 'VISIT_SAFETY_REVIEW_REQUIRED') ? _codes[code] : null;

/// Turns any failure into a short, clear Arabic sentence (never a raw exception or an English message).
String explainError(Object e, {String? fallback}) {
  if (e is DioException) {
    final data = e.response?.data;
    final code = data is Map ? data['code'] : null;
    if (code is String && _codes.containsKey(code)) return _codes[code]!;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى';
      default:
    }
    switch (e.response?.statusCode) {
      case 400:
        return fallback ?? 'البيانات المدخلة غير صالحة، راجعها وحاول مرة أخرى';
      case 401:
        return 'انتهت الجلسة، سجّل الدخول من جديد';
      case 403:
        return 'ليست لديك صلاحية لهذه العملية';
      case 404:
        return 'الخدمة غير متاحة حاليًا، حاول لاحقًا';
      case 409:
        return fallback ?? 'تعذر تنفيذ العملية في الحالة الحالية';
      case 413:
        return 'الملف كبير جدًا';
      case 429:
        return 'محاولات كثيرة، انتظر قليلًا ثم أعد المحاولة';
      case 500:
      case 502:
      case 503:
      case 504:
        return 'الخادم غير متاح حاليًا، حاول بعد قليل';
    }
  }
  return fallback ?? 'حدث خطأ غير متوقع، حاول مرة أخرى';
}
