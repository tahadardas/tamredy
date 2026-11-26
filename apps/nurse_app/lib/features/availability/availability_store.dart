import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import '../../availability_manager.dart';

class AvailabilityStore extends ChangeNotifier {
  final TamreedyApi api;
  final Future<void> Function(List<dynamic> offers) onOffersReceived;

  late final AvailabilityManager manager;

  String? toggleError;
  bool toggling = false;

  AvailabilityStore({
    required this.api,
    required this.onOffersReceived,
  }) {
    manager = AvailabilityManager(api: api, onOffersReceived: onOffersReceived);
    manager.addListener(notifyListeners);
  }

  bool get intentAvailable => manager.intentAvailable;
  NurseReadinessState get state => manager.state;
  bool get isReady => manager.isReady;
  List<String> get unmetRequirements => manager.unmetRequirements;
  Position? get currentPosition => manager.currentPosition;
  DateTime? get lastLocationUpdate => manager.lastLocationUpdate;

  void setActiveAssignment(bool active) => manager.setActiveAssignment(active);

  Future<void> setAvailability(bool available) async {
    if (toggling) return;
    toggling = true;
    toggleError = null;
    notifyListeners();
    try {
      await manager.setAvailability(available);
      await api.writeLocal('nurse_last_availability_intent', available ? 'AVAILABLE' : 'OFFLINE');
    } catch (e) {
      toggleError = explainError(
        e,
        fallback: 'تعذر تحديث حالة التوفر. تأكد من الاتصال وأذونات الموقع.',
      );
    } finally {
      toggling = false;
      notifyListeners();
    }
  }

  Future<void> restoreSavedIntent() async {
    final saved = await api.readLocal('nurse_last_availability_intent');
    if (saved == 'AVAILABLE' && !manager.hasActiveAssignment) {
      try {
        await manager.setAvailability(true);
      } catch (_) {}
    }
  }

  Future<void> syncNow() => manager.syncNow();

  Future<void> resetForSessionChange() async {
    await manager.setAvailability(false).catchError((_) {});
    await api.writeLocal('nurse_last_availability_intent', null);
    toggleError = null;
    toggling = false;
    notifyListeners();
  }

  @override
  void dispose() {
    manager.removeListener(notifyListeners);
    manager.dispose();
    super.dispose();
  }
}
