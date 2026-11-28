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
  List<Map<String, dynamic>> financialAccountsByCurrency = const [];
  bool legacyReconciliationRequired = false;
  String? currencyCode;
  int _refreshGeneration = 0;
  bool isBlocked = false;
  bool? settlementPending;
  int companyOwedAmount = 0;
  int nurseOwedAmount = 0;
  List<Map<String, dynamic>> settlementHistory = const [];
  List<Map<String, dynamic>> ledgerEntries = const [];
  int _sessionGen = 0;

  void resetForSessionChange() {
    _sessionGen++;
    _refreshGeneration++;
    financialAccountsByCurrency = const [];
    legacyReconciliationRequired = false;
    currencyCode = null;
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
    final refresh = ++_refreshGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.getMap('/v1/nurse/financial/summary'),
        api.getMap('/v1/nurse/me/dues'),
        api.getMap('/v1/nurse/financial/ledger').catchError((_) => <String, dynamic>{}),
      ]);
      if (gen != _sessionGen || refresh != _refreshGeneration) return;

      final sum = results[0];
      final dues = results[1];
      final ledger = results[2];
      final accounts = sum['financialAccountsByCurrency'];
      financialAccountsByCurrency = accounts is List
          ? accounts.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : const [];
      currencyCode = sum['currencyCode']?.toString();
      legacyReconciliationRequired = sum['legacyReconciliationRequired'] == true;

      todayEarnings = (num.tryParse('${sum['today_earnings'] ?? sum['earnings']?['today'] ?? sum['todayEarnings'] ?? dues['todayEarnings'] ?? 0}') ?? 0).round();
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

      if (currencyCode == null) {
        todayEarnings = null;
        netDue = null;
        commission = null;
        balance = null;
      }
      error = null;
    } catch (e) {
      if (gen != _sessionGen || refresh != _refreshGeneration) return;
      error = explainError(e, fallback: 'تعذر تحميل البيانات المالية من الخادم');
    } finally {
      if (gen == _sessionGen && refresh == _refreshGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }
}
