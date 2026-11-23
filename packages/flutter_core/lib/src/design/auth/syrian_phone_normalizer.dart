/// Syrian Mobile Normalizer and Validator Utility
/// Enforces local input format 09XXXXXXXX and canonical E.164 +9639XXXXXXXX format.
class SyrianPhoneNormalizer {
  static const String countryPrefix = '+963';
  static const int localLength = 10;
  static final RegExp _localPattern = RegExp(r'^09\d{8}$');

  /// Converts Arabic-Indic and Eastern Arabic digits (٠-٩) to Latin digits (0-9).
  static String convertArabicIndicDigits(String input) {
    const arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const easternArabic = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var result = input;
    for (int i = 0; i < 10; i++) {
      result = result.replaceAll(arabicIndic[i], i.toString());
      result = result.replaceAll(easternArabic[i], i.toString());
    }
    return result;
  }

  /// Sanitizes raw input: strips spaces, dashes, parentheses, non-digit chars (except leading plus).
  static String sanitize(String input) {
    final converted = convertArabicIndicDigits(input.trim());
    return converted.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
  }

  /// Converts any valid Syrian phone input (local 09XXXXXXXX or international +9639XXXXXXXX)
  /// into standard local format: 09XXXXXXXX (10 digits).
  /// Returns null if the input cannot be resolved to a valid Syrian mobile number.
  static String? toLocalSyrianMobile(String rawInput) {
    var cleaned = sanitize(rawInput);
    if (cleaned.isEmpty) return null;

    // Handle pasted international format +9639... or 009639...
    if (cleaned.startsWith('+963')) {
      cleaned = cleaned.substring(4);
      if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
      cleaned = '0$cleaned';
    } else if (cleaned.startsWith('00963')) {
      cleaned = cleaned.substring(5);
      if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
      cleaned = '0$cleaned';
    } else if (cleaned.startsWith('963')) {
      cleaned = cleaned.substring(3);
      if (cleaned.startsWith('0')) cleaned = cleaned.substring(1);
      cleaned = '0$cleaned';
    } else if (cleaned.startsWith('9') && cleaned.length == 9) {
      cleaned = '0$cleaned';
    }

    if (_localPattern.hasMatch(cleaned)) {
      return cleaned;
    }
    return null;
  }

  /// Normalizes a local Syrian mobile (09XXXXXXXX) into canonical E.164 format (+9639XXXXXXXX).
  /// Strips the leading zero and prepends +963.
  /// Never produces invalid numbers like +96309...
  static String? normalizeSyrianMobile(String rawInput) {
    final local = toLocalSyrianMobile(rawInput);
    if (local == null) return null;
    // local is 09XXXXXXXX -> drop '0' and prepend +963
    final significant = local.substring(1); // 9XXXXXXXX
    return '$countryPrefix$significant';
  }

  /// Validates Syrian phone input and returns null if valid, or a friendly localized Arabic error message.
  static String? validateSyrianMobile(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'يرجى إدخال رقم الهاتف';
    }
    final cleaned = sanitize(value);
    if (cleaned.length < 2) {
      return 'يرجى إدخال رقم هاتف صحيح';
    }
    if (!cleaned.startsWith('09') && !cleaned.startsWith('+963') && !cleaned.startsWith('9')) {
      return 'يجب أن يبدأ الرقم بـ 09';
    }
    final local = toLocalSyrianMobile(value);
    if (local == null) {
      if (cleaned.length != localLength) {
        return 'رقم الهاتف يجب أن يتكون من 10 أرقام (09XXXXXXXX)';
      }
      return 'رقم هاتف غير صالح، تأكد من كتابته بصيغة 09XXXXXXXX';
    }
    return null;
  }
}
