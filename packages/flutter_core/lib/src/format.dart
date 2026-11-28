import 'design/tokens/tam_status.dart';

/// Exact amount stored as integer minor units at an explicit decimal scale.
class MoneyAmount {
  const MoneyAmount(this.amountMinor, this.currencyCode, this.decimalPlaces);
  final BigInt amountMinor;
  final String currencyCode;
  final int decimalPlaces;

  factory MoneyAmount.parse(Object value, String currencyCode, {int? decimalPlaces}) {
    final match = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$').firstMatch('$value');
    if (match == null) throw const FormatException('Invalid money amount');
    final fraction = match.group(3) ?? '';
    final significant = fraction.replaceFirst(RegExp(r'0+$'), '');
    final scale = decimalPlaces == null || decimalPlaces < significant.length
        ? (decimalPlaces == null ? fraction.length : significant.length) : decimalPlaces;
    if (scale > 8) throw const FormatException('Unsupported money precision');
    final minor = BigInt.parse('${match.group(2)}${significant.padRight(scale, '0')}');
    return MoneyAmount(match.group(1) == '-' ? -minor : minor, currencyCode, scale);
  }

  String get decimalValue {
    final digits = amountMinor.abs().toString().padLeft(decimalPlaces + 1, '0');
    final split = digits.length - decimalPlaces;
    final fraction = decimalPlaces == 0 ? '' : '.${digits.substring(split)}';
    return '${amountMinor.isNegative ? '-' : ''}${digits.substring(0, split)}$fraction';
  }

  MoneyAmount operator -(MoneyAmount other) {
    if (currencyCode != other.currencyCode) throw ArgumentError('Currency mismatch');
    final scale = decimalPlaces > other.decimalPlaces ? decimalPlaces : other.decimalPlaces;
    final ten = BigInt.from(10);
    return MoneyAmount(amountMinor * ten.pow(scale - decimalPlaces)
        - other.amountMinor * ten.pow(scale - other.decimalPlaces), currencyCode, scale);
  }

  String get formatted => formatMoney(decimalValue, currency: currencyCode);
}

/// Arabic display helpers. Digits stay Latin to match the approved designs.
String formatMoney(Object value, {String currency = 'ل.س'}) {
  final exact = MoneyAmount.parse(value, currency).decimalValue;
  final negative = exact.startsWith('-');
  final parts = (negative ? exact.substring(1) : exact).split('.');
  final digits = parts.first;
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final fraction = parts.length > 1 ? '.${parts[1]}' : '';
  final symbol = switch (currency) {
    'SYP_NEW' => 'ل.س جديدة', 'SYP_OLD' => 'ل.س قديمة', 'SYP' => 'ل.س (SYP)',
    'USD' => 'US\$', 'EUR' => '€', _ => currency,
  };
  return '${negative ? '−' : ''}$buf$fraction $symbol';
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatCountdown(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${twoDigits(s ~/ 60)}:${twoDigits(s % 60)}';
}

/// Maps a backend request status to Arabic copy.
String requestStatusAr(String status) {
  final parsed = TamRequestStatus.parse(status);
  if (parsed == TamRequestStatus.unknown) {
    return status.isEmpty ? parsed.labelAr : status;
  }
  return parsed.labelAr;
}
