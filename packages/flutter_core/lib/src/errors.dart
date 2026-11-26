import 'package:dio/dio.dart';
import 'core/api_models.dart';

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
  'TOO_MANY_BENEFICIARIES': 'بلغت الحد الأقصى لعدد المستفيدين',
  'BENEFICIARY_CONSENT_REQUIRED': 'يلزم تأكيد الموافقة لإضافة المستفيد',
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
  'REQUEST_ALREADY_ASSIGNED_OR_CLOSED': 'تم إسناد هذا الطلب أو إغلاقه بالفعل',
  'REQUEST_CANNOT_BE_CANCELLED': 'لا يمكن إلغاء الطلب في حالته الحالية',
  'PROMO_NOT_FOUND': 'كود الخصم غير صحيح',
  'PROMO_EXPIRED': 'كود الخصم منتهي',
  'PROMO_ALREADY_USED': 'استخدمت هذا الكود من قبل',
  'APPLICATION_ALREADY_OPEN': 'لديك طلب انضمام قيد المراجعة بهذا الرقم، سنتواصل معك',
  'LICENSE_EXPIRED': 'الوثيقة منتهية الصلاحية؛ ارفع وثيقة سارية',
  'ROLE_NOT_ALLOWED': 'هذا الحساب غير مخصص لهذا التطبيق',
  'ROLE_APP_MISMATCH': 'عدم تطابق نوع الحساب مع التطبيق',
  'REQUEST_NOT_OPEN': 'الطلب لم يعد متاحاً لاستقبال عروض الجاهزية',
  'REQUEST_EXPIRED': 'انتهت مهلة استقبال العروض لهذا الطلب',
  'ARRIVAL_TIME_IN_PAST': 'وقت الوصول المقترح يجب أن يكون في المستقبل',
  'ARRIVAL_TIME_NOT_ACCEPTABLE': 'وقت الوصول المقترح يتجاوز الحد المقبول للمريض',
  'MAX_CONCURRENT_PROPOSALS_EXCEEDED': 'بلغت الحد الأقصى للعروض النشطة في الوقت نفسه',
  'NURSE_SCHEDULE_CONFLICT': 'لديك موعد أو زيارة أخرى تتعارض مع هذا التوقيت',
  'MISSING_REQUIRED_SKILLS': 'هذا الطلب يتطلب مهارات أو اعتماداً غير مفعّل في حسابك',
  'NURSE_NO_ACTIVE_REGION': 'لم يتم تحديد منطقة عمل نشطة لحسابك',
  'NURSE_REGION_MISMATCH': 'الطلب خارج نطاق مناطق عملك المعتمدة',
  'OFF_HOURS_UNAVAILABLE': 'حسابك غير متاح حالياً لاستقبال الطلبات',
  'PROPOSAL_NOT_FOUND_OR_NOT_PENDING': 'العرض غير موجود أو لم يعد قيد الانتظار',
  'PROPOSAL_EXPIRED': 'انتهت مدة صلاحية هذا العرض',
  'PROPOSAL_NOT_PENDING': 'هذا العرض لم يعد متاحاً',
  'PROPOSAL_VERSION_CONFLICT': 'تم تحديث العرض، يرجى إعادة المحاولة',
  'WALLET_NOT_ENABLED': 'المحفظة الإلكترونية غير مفعلة حاليًا؛ الدفع نقدي عند الزيارة',
  'CLINICAL_VISIT_NOTE_REQUIRED': 'يرجى توثيق الملاحظات السريرية للزيارة قبل إنهائها',
  'REQUEST_ITEMS_REQUIRE_OUTCOME': 'يجب تحديد نتيجة تنفيذ كل خدمة قبل إنهاء الزيارة',
  'NO_SERVICE_ITEM_COMPLETED': 'لا يمكن إنهاء الزيارة دون تنفيذ خدمة واحدة على الأقل',
  'ARRIVAL_GEOFENCE_FAILED': 'موقعك الحالي بعيد عن عنوان الزيارة؛ أضف سبب الاستثناء للمتابعة',
};

String? nightPolicyMessage(Object? code) =>
    code is String && (code.startsWith('NIGHT_POLICY_') || code.startsWith('VISIT_COMPANION_') || code == 'VISIT_SAFETY_REVIEW_REQUIRED')
        ? _codes[code]
        : null;

ApiFailure mapApiFailure(Object e, {String? fallback}) {
  if (e is ApiFailure) return e;
  if (e is DioException) {
    if (e.type == DioExceptionType.cancel) {
      return const ApiFailure(
        kind: ApiErrorKind.cancelled,
        messageAr: 'تم إلغاء الطلب',
      );
    }
    if (e.type == DioExceptionType.connectionError) {
      return ApiFailure(
        kind: ApiErrorKind.offline,
        messageAr: 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مجدداً.',
        raw: e,
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return ApiFailure(
        kind: ApiErrorKind.timeout,
        messageAr: 'انتهت مهلة الاتصال بالخادم. الشبكة بطيئة أو الخادم مشغول.',
        raw: e,
      );
    }

    final status = e.response?.statusCode;
    final data = e.response?.data;
    final code = data is Map ? (data['code'] ?? data['message'])?.toString() : null;
    final mappedCode = (code != null && _codes.containsKey(code)) ? _codes[code]! : null;

    switch (status) {
      case 400:
      case 422:
        return ApiFailure(
          kind: ApiErrorKind.validation,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? fallback ?? 'البيانات المدخلة غير صالحة، راجعها وحاول مرة أخرى',
          raw: e,
        );
      case 401:
        return ApiFailure(
          kind: ApiErrorKind.sessionExpired,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول مجدداً',
          raw: e,
        );
      case 403:
        return ApiFailure(
          kind: ApiErrorKind.forbidden,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'ليست لديك صلاحية لتنفيذ هذا الإجراء',
          raw: e,
        );
      case 404:
      case 410:
        return ApiFailure(
          kind: ApiErrorKind.notFound,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'العنصر المطلوب غير موجود أو انتهت صلاحيته',
          raw: e,
        );
      case 409:
        return ApiFailure(
          kind: ApiErrorKind.conflict,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? fallback ?? 'تعارض مع حالة الطلب الحالية، يرجى التحديث',
          raw: e,
        );
      case 413:
        return ApiFailure(
          kind: ApiErrorKind.validation,
          statusCode: status,
          code: code,
          messageAr: 'حجم الملف كبير جداً',
          raw: e,
        );
      case 429:
        return ApiFailure(
          kind: ApiErrorKind.rateLimited,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'محاولات كثيرة متتالية، انتظر قليلاً ثم أعد المحاولة',
          raw: e,
        );
      case 501:
        return ApiFailure(
          kind: ApiErrorKind.featureUnavailable,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'هذه الميزة غير مفعّلة حالياً',
          raw: e,
        );
      case 502:
      case 503:
      case 504:
        return ApiFailure(
          kind: ApiErrorKind.serverUnavailable,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'الخادم غير متاح حالياً، حاول بعد قليل',
          raw: e,
        );
      case 500:
        return ApiFailure(
          kind: ApiErrorKind.internalError,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? 'حدث خطأ داخلي في الخادم، حاول بعد قليل',
          raw: e,
        );
      default:
        return ApiFailure(
          kind: ApiErrorKind.unknown,
          statusCode: status,
          code: code,
          messageAr: mappedCode ?? fallback ?? 'تعذر إتمام الطلب، حاول مرة أخرى',
          raw: e,
        );
    }
  }
  return ApiFailure(
    kind: ApiErrorKind.unknown,
    messageAr: fallback ?? 'حدث خطأ غير متوقع، حاول مرة أخرى',
    raw: e,
  );
}

/// Turns any failure into a short, clear Arabic sentence (never a raw exception or an English message).
String explainError(Object e, {String? fallback}) =>
    mapApiFailure(e, fallback: fallback).messageAr;

/// Returns true only for transient transport/server-availability failures suitable for safe idempotent retry.
bool isTransientError(Object e) {
  final failure = mapApiFailure(e);
  return failure.kind == ApiErrorKind.offline ||
      failure.kind == ApiErrorKind.timeout ||
      failure.kind == ApiErrorKind.serverUnavailable;
}
