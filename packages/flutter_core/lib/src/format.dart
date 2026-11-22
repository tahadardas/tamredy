/// Arabic display helpers. Digits stay Latin to match the approved designs.
String formatMoney(num value, {String currency = 'ل.س'}) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return '${negative ? '−' : ''}$buf $currency';
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String formatCountdown(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${twoDigits(s ~/ 60)}:${twoDigits(s % 60)}';
}

/// Maps a backend request status to Arabic copy.
String requestStatusAr(String status) {
  switch (status) {
    case 'DRAFT':
    case 'REQUESTED':
    case 'OFFERING':
      return 'قيد البحث';
    case 'ASSIGNED':
      return 'تم الإسناد';
    case 'EN_ROUTE':
      return 'في الطريق';
    case 'ARRIVED':
      return 'وصل الممرض';
    case 'IN_SERVICE':
      return 'قيد التنفيذ';
    case 'COMPLETED':
      return 'مكتملة';
    case 'CANCELLED':
      return 'ملغاة';
    case 'UNFULFILLED':
      return 'غير مستجاب';
    case 'ESCALATED':
      return 'مرفوع للإشراف';
    default:
      return status;
  }
}
