import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/src/design/auth/syrian_phone_normalizer.dart';

void main() {
  group('SyrianPhoneNormalizer', () {
    test('standard local format 0987080330 converts to +963987080330', () {
      expect(
        SyrianPhoneNormalizer.normalizeSyrianMobile('0987080330'),
        '+963987080330',
      );
      expect(
        SyrianPhoneNormalizer.toLocalSyrianMobile('0987080330'),
        '0987080330',
      );
      expect(
        SyrianPhoneNormalizer.validateSyrianMobile('0987080330'),
        isNull,
      );
    });

    test('arabic indic digits ٠٩٨٧٠٨٠٣٣٠ converts accurately', () {
      expect(
        SyrianPhoneNormalizer.normalizeSyrianMobile('٠٩٨٧٠٨٠٣٣٠'),
        '+963987080330',
      );
      expect(
        SyrianPhoneNormalizer.toLocalSyrianMobile('٠٩٨٧٠٨٠٣٣٠'),
        '0987080330',
      );
      expect(
        SyrianPhoneNormalizer.validateSyrianMobile('٠٩٨٧٠٨٠٣٣٠'),
        isNull,
      );
    });

    test('pasted international E.164 +963987080330 normalizes correctly', () {
      expect(
        SyrianPhoneNormalizer.toLocalSyrianMobile('+963987080330'),
        '0987080330',
      );
      expect(
        SyrianPhoneNormalizer.normalizeSyrianMobile('+963987080330'),
        '+963987080330',
      );
    });

    test('input with spaces, hyphens, and parentheses is sanitized', () {
      expect(
        SyrianPhoneNormalizer.normalizeSyrianMobile('0987-080-330'),
        '+963987080330',
      );
      expect(
        SyrianPhoneNormalizer.normalizeSyrianMobile(' 0987 080 330 '),
        '+963987080330',
      );
    });

    test('incomplete number is rejected', () {
      expect(SyrianPhoneNormalizer.normalizeSyrianMobile('098708033'), isNull);
      expect(
        SyrianPhoneNormalizer.validateSyrianMobile('098708033'),
        isNotNull,
      );
    });

    test('number not starting with 09 is rejected', () {
      expect(SyrianPhoneNormalizer.normalizeSyrianMobile('0812345678'), isNull);
      expect(
        SyrianPhoneNormalizer.validateSyrianMobile('0812345678'),
        'يجب أن يبدأ الرقم بـ 09',
      );
    });

    test('number longer than 10 digits is rejected', () {
      expect(SyrianPhoneNormalizer.normalizeSyrianMobile('09870803301'), isNull);
      expect(
        SyrianPhoneNormalizer.validateSyrianMobile('09870803301'),
        isNotNull,
      );
    });

    test('never generates +96309...', () {
      final normalized = SyrianPhoneNormalizer.normalizeSyrianMobile('0987080330');
      expect(normalized?.contains('+9630'), isFalse);
      expect(normalized, '+963987080330');
    });
  });
}
