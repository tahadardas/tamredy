import 'package:flutter/foundation.dart';
import 'package:tamreedy_core/tamreedy_core.dart';

/// Strict server-sourced financial store for Nurse Earnings, Dues & Ledger.
/// Zero hardcoded fallback figures in live mode.
class NurseFinanceStore extends ChangeNotifier {
  final TamreedyApi api;

  NurseFinanceStore({required this.api});

  bool loading = false;
  String? error;

  int? todayEarnings;
  int? netDue;
  int? monthVisits;
  int? commission;
  int? balance;
  bool isBlocked = false;
  bool? settlementPending;
  int companyOwedAmount = 0;
  int nurseOwedAmount = 0;
  List<Map<String, dynamic>> settlementHistory = const [];
  List<Map<String, dynamic>> ledgerEntries = const [];
  int _sessionGen = 0;

  void resetForSessionChange() {
    _sessionGen++;
    todayEarnings = null;
    netDue = null;
    monthVisits = null;
    commission = null;
    balance = null;
    isBlocked = false;
    settlementPending = null;
    companyOwedAmount = 0;
    nurseOwedAmount = 0;
    settlementHistory = const [];
    ledgerEntries = const [];
    loading = false;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (kDemoMode) {
      todayEarnings = 36000;
      netDue = 180000;
      monthVisits = 8;
      commission = 45000;
      balance = 12000;
      isBlocked = false;
      settlementHistory = const [];
      ledgerEntries = const [];
      error = null;
      notifyListeners();
      return;
    }

    final gen = _sessionGen;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.getMap('/v1/nurse/financial/summary'),
        api.getMap('/v1/nurse/me/dues'),
        api.getMap('/v1/nurse/financial/ledger').catchError((_) => <String, dynamic>{}),
      ]);
      if (gen != _sessionGen) return;

      final sum = results[0];
      final dues = results[1];
      final ledger = results[2];

      todayEarnings = (num.tryParse('${sum['today_earnings'] ?? sum['todayEarnings'] ?? dues['todayEarnings'] ?? 0}') ?? 0).round();
      netDue = (num.tryParse('${dues['netDue'] ?? dues['net'] ?? sum['net_balance'] ?? 0}') ?? 0).round();
      monthVisits = (num.tryParse('${dues['monthVisits'] ?? sum['completed_visits'] ?? 0}') ?? 0).toInt();
      commission = (num.tryParse('${dues['commission'] ?? sum['total_commission'] ?? 0}') ?? 0).round();
      balance = (num.tryParse('${dues['balance'] ?? sum['cash_balance'] ?? 0}') ?? 0).round();
      isBlocked = dues['blocked'] == true;
      companyOwedAmount = (num.tryParse('${dues['nurseOwesCompany'] ?? dues['cashHeld'] ?? 0}') ?? 0).round();
      nurseOwedAmount = (num.tryParse('${dues['companyOwesNurse'] ?? dues['prepaidBalance'] ?? 0}') ?? 0).round();

      final rawHist = dues['history'];
      settlementHistory = rawHist is List
          ? rawHist.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [];

      final rawLedger = ledger['items'] ?? ledger['entries'];
      ledgerEntries = rawLedger is List
          ? rawLedger.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : const [];

      error = null;
    } catch (e) {
      error = explainError(e, fallback: 'تعذر تحميل البيانات المالية من الخادم');
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}
